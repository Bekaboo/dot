/**
 * Background timer tools: `timer_start`, `timer_stop`, `timer_status`.
 *
 * A timer fires on a fixed cadence, like `uv_timer_start(repeat, callback)`.
 * Each fire runs an optional `onTick` callback, checks an optional shell
 * condition, and wakes the agent with a short notification: a tick, 'condition
 * met', or 'timeout'. The callback output, when there is any, rides along with
 * the wake. Timers are named by the agent, so every wake and the status list
 * are self-describing.
 */

import { setTimeout as sleep } from "node:timers/promises";

import type {
  ExtensionAPI,
  SessionEntry,
  ToolDefinition,
} from "@earendil-works/pi-coding-agent";

import { type Static, Type } from "typebox";

// Timer duration, polling, and notification defaults, in seconds.
const DEFAULT_TIMEOUT_SEC = 3_600;
const MIN_TIMEOUT_SEC = 1;

const DEFAULT_INTERVAL_SEC = 60;
const MIN_INTERVAL_SEC = 1;

// Condition execution deadlines, in milliseconds.
const MIN_CONDITION_TIMEOUT_MS = 1_000;
const MAX_CONDITION_TIMEOUT_MS = 30_000;

// Snapshot deadline and size cap for the optional `onTick` callback.
const ON_TICK_TIMEOUT_MS = 10_000;
const ON_TICK_MAX_LINES = 40;
const ON_TICK_MAX_CHARS = 4_000;

/**
 * Accepted timer ids.
 *
 * A slug rather than free text: the id is echoed in every notification, listed
 * by status, and would name a log file if timers ever launch jobs.
 */
const ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{2,39}$/;

/** Custom message type used for timer notifications. */
const NOTICE_TYPE = "timer";

/** How many finished timers are remembered for a late `timer_stop` reply. */
const RETIRED_HISTORY = 10;

/** Names that replay as timer start results, including the old combined tool. */
const START_TOOL_NAMES = new Set(["timer_start", "timer"]);

/** Names that replay as timer stop results, including the old combined tool. */
const STOP_TOOL_NAMES = new Set(["timer_stop", "timer"]);

/** Schema for the `timer_start` tool. */
const TimerStartParams = Type.Object({
  id: Type.String({
    description:
      "Timer name: short, unique, purpose-bearing, e.g. batch3-done or pa1-peek. You see it in every wake and in `timer_status`.",
  }),
  condition: Type.Optional(
    Type.String({
      description:
        "Optional shell predicate; exit code 0 ends the timer and wakes you with 'condition met'. Omit for a timer that only ticks.",
    }),
  ),
  onTick: Type.Optional(
    Type.String({
      description:
        "Optional shell command run at every tick interval. Its output, if any, is included in the wake when one is sent, so it can snapshot a job (`tail -n 20 /tmp/job.log`) or just do periodic work. It runs even when a wake is throttled or maxTicks is 0; it must never wait, so no sleep.",
    }),
  ),
  intervalSec: Type.Optional(
    Type.Number({
      description:
        "Seconds between ticks; also the delay before the first tick of a timer.",
      minimum: MIN_INTERVAL_SEC,
      default: DEFAULT_INTERVAL_SEC,
    }),
  ),
  maxTicks: Type.Optional(
    Type.Number({
      description:
        "Maximum tick wakes. 0 = never tick (condition timers only); omit = unlimited. A timer needs at least 1. The final 'condition met' or 'timeout' wake is always sent and does not count.",
      minimum: 0,
    }),
  ),
  timeoutSec: Type.Optional(
    Type.Number({
      description: "Lifetime cap in seconds.",
      minimum: MIN_TIMEOUT_SEC,
      default: DEFAULT_TIMEOUT_SEC,
    }),
  ),
});

/** Input accepted by the `timer_start` tool. */
type TimerStartInput = Static<typeof TimerStartParams>;

/** Schema for the `timer_stop` tool. */
const TimerStopParams = Type.Object({
  id: Type.String({ description: "Name of the timer to cancel." }),
});

/** Input accepted by the `timer_stop` tool. */
type TimerStopInput = Static<typeof TimerStopParams>;

/** Schema for the `timer_status` tool. */
const TimerStatusParams = Type.Object({
  id: Type.Optional(
    Type.String({
      description: "Timer to report; omit to list every active timer.",
    }),
  ),
});

/** Input accepted by the `timer_status` tool. */
type TimerStatusInput = Static<typeof TimerStatusParams>;

/** Kind of notification a timer emits. */
type TimerState = "tick" | "done" | "timeout" | "error";

/** Persisted specification of one timer. */
interface TimerSpec {
  /** Agent-chosen name, unique among active timers. */
  id: string;
  /** Shell predicate; exit code 0 means the timer is done. */
  condition?: string;
  /** Shell command whose output rides along with every wake. */
  onTick?: string;
  /** Tick cadence in seconds; also the delay before a timer's first tick. */
  intervalSec: number;
  /** Maximum tick wakes; `undefined` means unlimited. */
  maxTicks?: number;
  /** Lifetime cap in seconds. */
  timeoutSec: number;
  /** Unix timestamp in milliseconds when the timer was armed. */
  startedAt: number;
}

/** One active timer. */
interface Timer extends TimerSpec {
  /** Ticks actually delivered. */
  ticksSent: number;
  /** A notification is queued and not yet acted on by the agent. */
  noticePending: boolean;
  /** Set when the user or session teardown cancels the timer. */
  stopped: boolean;
  /** Aborts in-flight `pi.exec()` and sleep calls on cancellation. */
  controller: AbortController;
}

/** Details stored on a timer tool result. */
type TimerDetails =
  | ({ action: "start" } & TimerSpec)
  | { action: "stop"; id: string }
  | { action: "status"; id?: string };

/** Details stored on a timer notification. */
interface TimerNoticeDetails {
  /** Timer id that produced the notification. */
  id: string;
  /** Notification kind; used to retire a finished timer on replay. */
  state: TimerState;
}

/**
 * Build a timer tool result.
 *
 * @param text - Message shown to the model.
 * @param details - Structured details replayed on session restore.
 * @returns Tool result object.
 */
function timerResult(text: string, details: TimerDetails) {
  return { content: [{ type: "text" as const, text }], details };
}

/**
 * Read a required timer id and validate its shape.
 *
 * @param id - Raw id from the tool input, required by the schema.
 * @returns The validated id.
 */
function requireId(id: string): string {
  if (!id) {
    throw new Error("A timer id is required.");
  }
  if (!ID_PATTERN.test(id)) {
    throw new Error(
      `Invalid timer id "${id}": use 3-40 characters from A-Z a-z 0-9 . _ -, starting with a letter or digit, e.g. batch3-done.`,
    );
  }
  return id;
}

/**
 * Format elapsed seconds since a timer was armed.
 *
 * @param timer - Timer to measure.
 * @returns Whole seconds, e.g. `40s`.
 */
function elapsed(timer: Timer): string {
  return `${Math.floor((Date.now() - timer.startedAt) / 1000)}s`;
}

/**
 * Cap a callback snapshot so a noisy command cannot flood a wake.
 *
 * @param text - Raw stdout and stderr from the callback.
 * @returns At most `ON_TICK_MAX_LINES` lines and `ON_TICK_MAX_CHARS` chars.
 */
function clipOutput(text: string): string {
  const lines = text.split("\n");
  const kept = lines.slice(0, ON_TICK_MAX_LINES).join("\n");
  if (kept.length > ON_TICK_MAX_CHARS) {
    return `${kept.slice(0, ON_TICK_MAX_CHARS)}\n... (clipped)`;
  }
  if (lines.length > ON_TICK_MAX_LINES) {
    return `${kept}\n... (+${lines.length - ON_TICK_MAX_LINES} more lines)`;
  }
  return kept;
}

/**
 * Persisted fields of a timer.
 *
 * @param timer - Timer to serialize into tool-result details.
 * @returns The timer specification stored in the session branch.
 */
function toTimerSpec(timer: Timer): TimerSpec {
  return {
    id: timer.id,
    condition: timer.condition,
    onTick: timer.onTick,
    intervalSec: timer.intervalSec,
    maxTicks: timer.maxTicks,
    timeoutSec: timer.timeoutSec,
    startedAt: timer.startedAt,
  };
}

/**
 * Replay start, stop, and terminal notification entries from a session branch.
 *
 * @param entries - Active session branch entries.
 * @returns Active timer specifications keyed by id.
 */
function collectActiveTimers(
  entries: readonly SessionEntry[],
): Map<string, TimerSpec> {
  const active = new Map<string, TimerSpec>();

  for (const entry of entries) {
    if (entry.type === "message" && entry.message.role === "toolResult") {
      const { toolName } = entry.message;
      const details = entry.message.details as TimerDetails | undefined;
      if (details?.action === "start" && START_TOOL_NAMES.has(toolName)) {
        const { action: _action, ...spec } = details;
        active.set(spec.id, spec);
      }
      if (details?.action === "stop" && STOP_TOOL_NAMES.has(toolName)) {
        active.delete(details.id);
      }
      continue;
    }

    if (entry.type === "custom_message" && entry.customType === NOTICE_TYPE) {
      const details = entry.details as TimerNoticeDetails | undefined;
      if (details?.id && details.state !== "tick") {
        active.delete(details.id);
      }
    }
  }

  return active;
}

/**
 * Registry of background timers for one extension load.
 *
 * Owns the active-timer map and the poll loops, so the tool and session
 * handlers never touch timer bookkeeping directly.
 */
class TimerRegistry {
  private pi: ExtensionAPI;
  private timers: Map<string, Timer>;
  /**
   * Timers that ended on their own, newest last, mapped to how they ended.
   *
   * Kept so a late `timer_stop` reports "stopped" instead of failing with
   * "no such timer": after the wake that announced the end, stopping the
   * timer is the obvious next move, and it must not look like an error. Bounded
   * like the subagent history, so a long session of short timers cannot grow it
   * without limit.
   */
  private retired: Map<string, string>;

  /**
   * @param pi - Extension API used for command execution and notifications.
   */
  constructor(pi: ExtensionAPI) {
    this.pi = pi;
    this.timers = new Map();
    this.retired = new Map();
  }

  /**
   * Arm a timer and start polling it in the background.
   *
   * @param params - Validated `timer_start` input.
   * @returns The persisted specification of the new timer.
   */
  start(params: TimerStartInput): TimerSpec {
    const id = requireId(params.id);
    if (this.timers.has(id)) {
      throw new Error(
        `Timer "${id}" is already active; stop it first or pick another id.`,
      );
    }

    const condition = params.condition?.trim() || undefined;
    const timer: Timer = {
      id,
      condition,
      onTick: params.onTick?.trim() || undefined,
      intervalSec: params.intervalSec ?? DEFAULT_INTERVAL_SEC,
      maxTicks: params.maxTicks,
      timeoutSec: params.timeoutSec ?? DEFAULT_TIMEOUT_SEC,
      startedAt: Date.now(),
      ticksSent: 0,
      noticePending: false,
      stopped: false,
      controller: new AbortController(),
    };

    this.validateBudget(timer);
    this.arm(timer);
    return toTimerSpec(timer);
  }

  /**
   * Reject budgets that can never pay out.
   *
   * A timer with no ticks could never wake the agent, and a tick scheduled
   * after the deadline would silently never fire.
   *
   * @param timer - Timer about to be armed.
   */
  private validateBudget(timer: Timer): void {
    if (!timer.condition && timer.maxTicks === 0) {
      throw new Error(
        `Timer "${timer.id}" has no condition and maxTicks 0, so it could never wake you.`,
      );
    }

    if (this.canTick(timer) && timer.timeoutSec < timer.intervalSec) {
      throw new Error(
        `Timer "${timer.id}" cannot tick: timeoutSec ${timer.timeoutSec} is shorter than intervalSec ${timer.intervalSec}.`,
      );
    }
  }

  /**
   * Cancel one timer and stop its poll loop.
   *
   * @param id - Id of the timer to cancel.
   * @returns `true` when an active timer had that id.
   */
  stop(id: string): boolean {
    const timer = this.timers.get(id);
    if (!timer) {
      return false;
    }

    timer.stopped = true;
    timer.controller.abort();
    this.timers.delete(id);
    return true;
  }

  /**
   * Forget a timer that ended on its own, and how it ended.
   *
   * Removal from the active map happens here rather than only in the loop's
   * cleanup, so a `timer_stop` that races the farewell wake already sees a
   * stopped timer instead of a live one.
   *
   * @param id - Id of the timer that just finished.
   * @param reason - Why it finished, e.g. `tick budget spent`.
   */
  private retire(id: string, reason: string): void {
    this.timers.delete(id);
    this.retired.delete(id);
    this.retired.set(id, reason);
    // Oldest first: a re-inserted id moves to the end, so this drops the timer
    // the agent is least likely to still ask about.
    const oldest = this.retired.keys().next();
    if (!oldest.done && this.retired.size > RETIRED_HISTORY) {
      this.retired.delete(oldest.value);
    }
  }

  /**
   * Explain why a timer by this id has stopped.
   *
   * @param id - Id of a timer this call has confirmed is retired.
   * @returns A sentence ending in a period.
   */
  retirementText(id: string): string {
    return `Timer "${id}" stopped (${this.retired.get(id)}).`;
  }

  /** Cancel every active timer. */
  stopAll(): void {
    for (const timer of this.timers.values()) {
      timer.stopped = true;
      timer.controller.abort();
    }
    this.timers.clear();
    this.retired.clear();
  }

  /** Forget which timers still have a queued notification. */
  clearPending(): void {
    for (const timer of this.timers.values()) {
      timer.noticePending = false;
    }
  }

  /**
   * Describe every active timer, one line each.
   *
   * @returns Lines sorted by id, or a message when nothing is active.
   */
  list(): string {
    if (this.timers.size === 0) {
      return "No active timers.";
    }

    return [...this.timers.values()]
      .sort((left, right) => left.id.localeCompare(right.id))
      .map((timer) => this.describe(timer))
      .join("\n");
  }

  /**
   * Describe one timer.
   *
   * @param id - Id from the tool input.
   * @returns The one-line description of that timer.
   */
  status(id: string): string {
    const timer = this.timers.get(id);
    if (timer) {
      return this.describe(timer);
    }
    return this.retired.has(id) ? this.retirementText(id) : this.unknownId(id);
  }

  /**
   * Look up the timer a `timer_stop` call should cancel.
   *
   * Stopping a timer that ended on its own is not an error: the agent usually
   * stops it right after the wake that announced the end, and a failure there
   * teaches it nothing. Such a call returns `undefined` so the tool can report
   * that the timer stopped.
   *
   * @param id - Id from the tool input.
   * @returns The active timer, or `undefined` when it already ended by itself.
   */
  requireStopTarget(id: string): Timer | undefined {
    const timer = this.timers.get(id);
    if (timer || this.retired.has(id)) {
      return timer;
    }
    throw new Error(this.unknownId(id));
  }

  /**
   * Explain that no timer with this id is running or retired.
   *
   * @param id - Id from the tool input.
   * @returns An error message naming the ids that are active.
   */
  private unknownId(id: string): string {
    const active = [...this.timers.keys()].sort();
    return active.length === 0
      ? `No timer "${id}"; nothing is active.`
      : `No timer "${id}"; active: ${active.join(", ")}.`;
  }

  /**
   * Describe one timer as a single line.
   *
   * @param timer - Timer to describe.
   * @returns Id, state, age, tick budget, and condition.
   */
  private describe(timer: Timer): string {
    const ticks =
      timer.maxTicks === undefined
        ? `${timer.ticksSent}/unlimited`
        : `${timer.ticksSent}/${timer.maxTicks}`;
    const target = timer.condition
      ? `cond: ${timer.condition}`
      : "timer, no condition";
    return `${timer.id}  running  ${elapsed(timer)}  ticks ${ticks}  ${target}`;
  }

  /**
   * Replace the current timers with those recorded on a session branch.
   *
   * In-flight loops are cancelled first, so a branch switch cannot leave
   * orphaned pollers that keep notifying about an abandoned timeline.
   *
   * @param entries - Active session branch entries.
   */
  restore(entries: readonly SessionEntry[]): void {
    this.stopAll();

    for (const spec of collectActiveTimers(entries).values()) {
      this.arm({
        ...spec,
        ticksSent: 0,
        noticePending: false,
        stopped: false,
        controller: new AbortController(),
      });
    }
  }

  /**
   * Register a timer and start its poll loop without blocking the caller.
   *
   * @param timer - Timer to arm.
   */
  private arm(timer: Timer): void {
    this.timers.set(timer.id, timer);
    this.retired.delete(timer.id);
    void this.poll(timer)
      .catch((error) => {
        // Same ownership reason as the `finally` below: a loop replaced by
        // `restore()` must not retire the timer that replaced it.
        if (!timer.stopped && this.timers.get(timer.id) === timer) {
          this.retire(timer.id, "failed");
          this.notify(timer, "error", `error: ${String(error)}; timer stopped`);
        }
      })
      .finally(() => {
        // Ownership check:
        // `restore()` aborts old loops and immediately re-arms the same ids.
        // An old loop may finish after its replacement is in the map; deleting
        // by id alone would orphan the replacement timer, making it impossible
        // to stop. Only remove the entry if this loop still owns it.
        if (this.timers.get(timer.id) === timer) {
          this.timers.delete(timer.id);
        }
      });
  }

  /**
   * Whether the timer may still send a tick.
   *
   * @param timer - Timer to check.
   * @returns `true` when the tick budget is not exhausted.
   */
  private canTick(timer: Timer): boolean {
    return timer.maxTicks === undefined || timer.ticksSent < timer.maxTicks;
  }

  /**
   * Poll a timer until it succeeds, times out, or is cancelled.
   *
   * A condition timer checks once immediately, then on every tick. A timer
   * only ticks, and ends once its budget is spent because it has nothing left
   * to report. The wake that ends a timer says it stopped, so the agent is not
   * left guessing whether it is still armed.
   *
   * @param timer - Timer to run.
   */
  private async poll(timer: Timer): Promise<void> {
    const deadline = timer.startedAt + timer.timeoutSec * 1000;

    if (
      timer.condition &&
      (await this.matches(timer, timer.condition, deadline))
    ) {
      await this.finish(timer, "done");
      return;
    }

    while (!timer.stopped) {
      const waitMs = Math.min(timer.intervalSec * 1000, deadline - Date.now());
      if (waitMs > 0) {
        await sleep(waitMs, undefined, { signal: timer.controller.signal });
      }
      if (timer.stopped) {
        return;
      }

      if (Date.now() >= deadline) {
        await this.finish(timer, "timeout");
        return;
      }

      if (
        timer.condition &&
        (await this.matches(timer, timer.condition, deadline))
      ) {
        await this.finish(timer, "done");
        return;
      }

      // The callback is the timer body: it runs on every tick even when the
      // wake is throttled, so periodic work is never silently skipped.
      const body = await this.capture(timer);
      if (!this.canTick(timer) || timer.noticePending) {
        // Nothing was delivered, so neither the budget nor the timer moved: a
        // throttled wake still counts a tick, and this one was not sent.
        continue;
      }

      // Only a timer with no condition ends when it runs out of ticks: one with
      // a condition is still waiting for that condition to hold.
      const last = !timer.condition && !this.hasTicksLeft(timer);
      this.tick(timer, body, last);
      if (last) {
        // The tick just sent was the timer's farewell.
        this.retire(timer.id, "tick budget spent");
        return;
      }
    }
  }

  /**
   * Whether the budget has room for a tick after the one about to be sent.
   *
   * @param timer - Timer about to tick.
   * @returns `true` when another tick may follow; `false` when the next tick
   *   spends the budget, making it the timer's last.
   */
  private hasTicksLeft(timer: Timer): boolean {
    return timer.maxTicks === undefined || timer.ticksSent + 1 < timer.maxTicks;
  }

  /**
   * Run the timer's condition.
   *
   * @param timer - Timer the condition belongs to.
   * @param condition - Shell predicate to evaluate.
   * @param deadline - Unix timestamp in milliseconds when the timer expires.
   * @returns `true` when the condition exited 0.
   */
  private async matches(
    timer: Timer,
    condition: string,
    deadline: number,
  ): Promise<boolean> {
    const remaining = deadline - Date.now();
    const result = await this.pi.exec("bash", ["-lc", condition], {
      signal: timer.controller.signal,
      timeout: Math.min(
        MAX_CONDITION_TIMEOUT_MS,
        Math.max(MIN_CONDITION_TIMEOUT_MS, remaining),
      ),
    });
    return result.code === 0;
  }

  /**
   * Send one tick.
   *
   * Callers check the budget and the pending wake first: a throttled tick
   * still runs the callback, but it sends nothing and costs no budget.
   *
   * @param timer - Timer to tick.
   * @param body - Snapshot captured for this tick, possibly empty.
   * @param last - Whether this tick spends the budget, so nothing follows it.
   */
  private tick(timer: Timer, body: string, last: boolean): void {
    timer.ticksSent += 1;
    const count = `${timer.ticksSent}${timer.maxTicks === undefined ? "" : `/${timer.maxTicks}`}`;
    // A last tick carries the farewell, so the one wake the agent reads tells it
    // both the news and that the timer is gone.
    const ending = last ? "; timer stopped" : "";
    this.notify(
      timer,
      "tick",
      `tick ${count}, ${elapsed(timer)} elapsed${ending}`,
      body,
    );
  }

  /**
   * Run the optional `onTick` callback for one tick.
   *
   * The callback is the timer body, so it runs on every tick whether or not a
   * wake is sent; empty output is normal, since it may be periodic work.
   *
   * @param timer - Timer whose callback to run.
   * @returns Clipped output, or an empty string when no callback is set.
   */
  private async capture(timer: Timer): Promise<string> {
    if (!timer.onTick) {
      return "";
    }

    try {
      const result = await this.pi.exec("bash", ["-lc", timer.onTick], {
        signal: timer.controller.signal,
        timeout: ON_TICK_TIMEOUT_MS,
      });
      return clipOutput(`${result.stdout}${result.stderr}`.trim());
    } catch (error) {
      // A broken callback must not kill the timer that reports on the job.
      if (timer.stopped) {
        return "";
      }
      return `onTick failed: ${String(error)}`;
    }
  }

  /**
   * Send the final notification of a timer and retire it.
   *
   * @param timer - Timer that finished.
   * @param state - Why it finished.
   */
  private async finish(timer: Timer, state: "done" | "timeout"): Promise<void> {
    const body = await this.capture(timer);
    if (state === "done") {
      this.retire(timer.id, "condition met");
      this.notify(
        timer,
        "done",
        `condition met after ${elapsed(timer)}: ${timer.condition}; timer stopped`,
        body,
      );
      return;
    }
    this.retire(timer.id, "timed out");
    this.notify(
      timer,
      "timeout",
      `timeout after ${timer.timeoutSec}s; timer stopped`,
      body,
    );
  }

  /**
   * Deliver a timer update to the agent.
   *
   * Uses `steer` so the wake is delivered before the next model request, even
   * mid-turn; when idle it starts a new turn.
   *
   * @param timer - Timer that produced the update.
   * @param state - Notification kind.
   * @param line - One-line body with the timer name and the news.
   * @param body - Optional snapshot captured by `onTick`.
   */
  private notify(
    timer: Timer,
    state: TimerState,
    line: string,
    body = "",
  ): void {
    timer.noticePending = true;
    const content = body
      ? `[timer ${timer.id}] ${line}\n${body}`
      : `[timer ${timer.id}] ${line}`;
    this.pi.sendMessage(
      {
        customType: NOTICE_TYPE,
        content,
        display: true,
        details: { id: timer.id, state },
      },
      { triggerTurn: true, deliverAs: "steer" },
    );
  }
}

/**
 * Describe what a freshly armed timer will do.
 *
 * @param spec - Specification returned by the registry.
 * @returns One-line summary for the tool result.
 */
function describeStart(spec: TimerSpec): string {
  const ticks =
    spec.maxTicks === undefined
      ? `tick every ${spec.intervalSec}s`
      : spec.maxTicks === 0
        ? "no ticks"
        : spec.maxTicks === 1
          ? `one tick after ${spec.intervalSec}s`
          : `tick every ${spec.intervalSec}s, at most ${spec.maxTicks}`;
  const ending = spec.condition
    ? `it ends when the condition first exits 0 or after ${spec.timeoutSec}s`
    : `it ends after that tick or at its ${spec.timeoutSec}s timeout`;
  return `Started "${spec.id}": ${ticks}; ${ending}. Wakes arrive even after you end your turn.`;
}

/**
 * Build the `timer_start` tool definition.
 *
 * @param registry - Timer registry shared with the session handlers.
 * @returns Tool definition registered with Pi.
 */
function timerStartTool(
  registry: TimerRegistry,
): ToolDefinition<typeof TimerStartParams, TimerDetails> {
  return {
    name: "timer_start",
    label: "Timer start",
    description:
      "Arm a named background timer that fires every intervalSec, running an optional onTick callback and an optional shell condition, and wakes you with a short notification (a tick, 'condition met', or 'timeout'). It returns immediately. The wake carries the onTick output when there is any, and otherwise just the event: read the job yourself so a queued wake cannot mislead you.",
    promptSnippet:
      "Defer a wake: fire every interval, run a callback, and wake the agent on a tick or when a condition becomes true",
    promptGuidelines: [
      "Name every `timer_start` with a short, unique, purpose-bearing id (batch3-done, pa1-peek, log1-monitor): the id is what you see in every wake, so it must remind you what you are waiting for.",
      "Use `timer_start` instead of `sleep N; ...` in bash. Start the timer, then keep working or end your turn; ending a turn loses nothing because the wake starts a new turn when you are idle.",
      "For a single deferred look, call `timer_start` with no condition, `intervalSec=N` and `maxTicks=1`: one wake after N seconds, then the timer ends.",
      "For 'tell me when it finishes', give `timer_start` a condition and `maxTicks=0`: no ticks, one wake when the condition exits 0.",
      "For work that must happen every interval, put it in `timer_start`'s `onTick`; it runs on every fire, even when the wake itself is throttled.",
      "A timer wake says only that something happened. After a wake, run the check you actually need, then call `timer_stop` once you no longer care.",
    ],
    parameters: TimerStartParams,

    async execute(_toolCallId: string, params: TimerStartInput) {
      const spec = registry.start(params);
      return timerResult(describeStart(spec), { action: "start", ...spec });
    },
  };
}

/**
 * Build the `timer_stop` tool definition.
 *
 * @param registry - Timer registry shared with the session handlers.
 * @returns Tool definition registered with Pi.
 */
function timerStopTool(
  registry: TimerRegistry,
): ToolDefinition<typeof TimerStopParams, TimerDetails> {
  return {
    name: "timer_stop",
    label: "Timer stop",
    description: "Cancel a running timer so it stops ticking and waking you.",
    parameters: TimerStopParams,

    async execute(_toolCallId: string, params: TimerStopInput) {
      const id = requireId(params.id);
      const timer = registry.requireStopTarget(id);
      if (!timer) {
        return timerResult(registry.retirementText(id), { action: "stop", id });
      }
      registry.stop(id);
      return timerResult(`Stopped "${id}".`, { action: "stop", id });
    },
  };
}

/**
 * Build the `timer_status` tool definition.
 *
 * @param registry - Timer registry shared with the session handlers.
 * @returns Tool definition registered with Pi.
 */
function timerStatusTool(
  registry: TimerRegistry,
): ToolDefinition<typeof TimerStatusParams, TimerDetails> {
  return {
    name: "timer_status",
    label: "Timer status",
    description:
      "Report every active timer: id, age, ticks spent, and what it waits for. Name an id to report just that timer.",
    parameters: TimerStatusParams,

    async execute(_toolCallId: string, params: TimerStatusInput) {
      if (!params.id) {
        return timerResult(registry.list(), { action: "status" });
      }
      const id = requireId(params.id);
      return timerResult(registry.status(id), { action: "status", id });
    },
  };
}

/**
 * Register the timer extension with Pi.
 *
 * @param pi - Extension API used to register the tools and session cleanup.
 */
export default function timer(pi: ExtensionAPI): void {
  const registry = new TimerRegistry(pi);

  pi.registerTool(timerStartTool(registry));
  pi.registerTool(timerStopTool(registry));
  pi.registerTool(timerStatusTool(registry));

  pi.on("session_start", async (_event, ctx) => {
    registry.restore(ctx.sessionManager.getBranch());
  });

  pi.on("session_tree", async (_event, ctx) => {
    registry.restore(ctx.sessionManager.getBranch());
  });

  // Any tool call means the agent acted on the last wake, so the next tick may
  // be delivered again. `agent_start` covers runs that begin without a tool.
  pi.on("tool_call", async () => registry.clearPending());
  pi.on("agent_start", async () => registry.clearPending());

  pi.on("session_shutdown", async () => registry.stopAll());
}
