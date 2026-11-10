/**
 * Background watch tool.
 *
 * A watch polls an optional shell predicate on a fixed cadence and wakes the
 * agent with a short, content-free notification: a tick, a met condition, or a
 * timeout. The agent reads the job's output itself after a wake, so a queued
 * notification never goes stale. Watches are named by the agent, so every wake
 * and the status list are self-describing.
 */

import { setTimeout as sleep } from "node:timers/promises";

import { StringEnum } from "@earendil-works/pi-ai";
import type {
  ExtensionAPI,
  SessionEntry,
} from "@earendil-works/pi-coding-agent";

import { type Static, Type } from "typebox";

// Watch duration, polling, and notification defaults, in seconds.
const DEFAULT_TIMEOUT_SEC = 3_600;
const MIN_TIMEOUT_SEC = 1;

const DEFAULT_INTERVAL_SEC = 60;
const MIN_INTERVAL_SEC = 1;

// Condition execution deadlines, in milliseconds.
const MIN_CONDITION_TIMEOUT_MS = 1_000;
const MAX_CONDITION_TIMEOUT_MS = 30_000;

/**
 * Accepted watch ids.
 *
 * A slug rather than free text: the id is echoed in every notification, listed
 * by status, and would name a log file if watches ever launch jobs.
 */
const ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{2,39}$/;

/** Custom message type used for watch notifications. */
const NOTICE_TYPE = "watch";

/** Schema for the `watch` tool. */
const WatchParams = Type.Object({
  action: StringEnum(["start", "stop", "status"] as const, {
    description:
      "start arms a named watch; stop cancels it; status reports one watch or all of them.",
  }),
  id: Type.Optional(
    Type.String({
      description:
        "start/stop: required watch name. Short, unique, purpose-bearing, e.g. batch3-done or pa1-peek: you see it in every wake and in status. status: optional; omit to list every active watch.",
    }),
  ),
  condition: Type.Optional(
    Type.String({
      description:
        "start: optional shell predicate; exit code 0 ends the watch and wakes you with 'condition met'. Omit for a timer that only ticks.",
    }),
  ),
  intervalSec: Type.Optional(
    Type.Number({
      description:
        "start: seconds between ticks; also the delay before the first tick of a timer.",
      minimum: MIN_INTERVAL_SEC,
      default: DEFAULT_INTERVAL_SEC,
    }),
  ),
  maxTicks: Type.Optional(
    Type.Number({
      description:
        "start: maximum tick wakes. 0 = never tick (condition watches only); omit = unlimited. A timer needs at least 1. The final 'condition met' or 'timeout' wake is always sent and does not count.",
      minimum: 0,
    }),
  ),
  timeoutSec: Type.Optional(
    Type.Number({
      description: "start: lifetime cap in seconds.",
      minimum: MIN_TIMEOUT_SEC,
      default: DEFAULT_TIMEOUT_SEC,
    }),
  ),
});

/** Input accepted by the `watch` tool. */
type WatchInput = Static<typeof WatchParams>;

/** Kind of notification a watch emits. */
type WatchState = "tick" | "done" | "timeout" | "error";

/** Persisted specification of one watch. */
interface WatchSpec {
  /** Agent-chosen name, unique among active watches. */
  id: string;
  /** Shell predicate; exit code 0 means the watch is done. */
  condition?: string;
  /** Tick cadence in seconds; also the delay before a timer's first tick. */
  intervalSec: number;
  /** Maximum tick wakes; `undefined` means unlimited. */
  maxTicks?: number;
  /** Lifetime cap in seconds. */
  timeoutSec: number;
  /** Unix timestamp in milliseconds when the watch was armed. */
  startedAt: number;
}

/** One active watch. */
interface Watch extends WatchSpec {
  /** Ticks actually delivered. */
  ticksSent: number;
  /** A notification is queued and not yet acted on by the agent. */
  noticePending: boolean;
  /** Set when the user or session teardown cancels the watch. */
  stopped: boolean;
  /** Aborts in-flight `pi.exec()` and sleep calls on cancellation. */
  controller: AbortController;
}

/** Details stored on a `watch` tool result. */
type WatchDetails =
  | ({ action: "start" } & WatchSpec)
  | { action: "stop"; id: string }
  | { action: "status"; id?: string };

/** Details stored on a watch notification. */
interface WatchNoticeDetails {
  /** Watch id that produced the notification. */
  id: string;
  /** Notification kind; used to retire a finished watch on replay. */
  state: WatchState;
}

/**
 * Build a `watch` tool result.
 *
 * @param text - Message shown to the model.
 * @param details - Structured details replayed on session restore.
 * @returns Tool result object.
 */
function watchResult(text: string, details: WatchDetails) {
  return { content: [{ type: "text" as const, text }], details };
}

/**
 * Read a required watch id and validate its shape.
 *
 * @param id - Raw id from the tool input.
 * @param action - Action that needs the id, for the error message.
 * @returns The validated id.
 */
function requireId(id: string | undefined, action: string): string {
  if (!id) {
    throw new Error(`action=${action} requires id.`);
  }
  if (!ID_PATTERN.test(id)) {
    throw new Error(
      `Invalid watch id "${id}": use 3-40 characters from A-Z a-z 0-9 . _ -, starting with a letter or digit, e.g. batch3-done.`,
    );
  }
  return id;
}

/**
 * Format elapsed seconds since a watch was armed.
 *
 * @param watch - Watch to measure.
 * @returns Whole seconds, e.g. `40s`.
 */
function elapsed(watch: Watch): string {
  return `${Math.floor((Date.now() - watch.startedAt) / 1000)}s`;
}

/**
 * Persisted fields of a watch.
 *
 * @param watch - Watch to serialize into tool-result details.
 * @returns The watch specification stored in the session branch.
 */
function toWatchSpec(watch: Watch): WatchSpec {
  return {
    id: watch.id,
    condition: watch.condition,
    intervalSec: watch.intervalSec,
    maxTicks: watch.maxTicks,
    timeoutSec: watch.timeoutSec,
    startedAt: watch.startedAt,
  };
}

/**
 * Whether a start entry predates the content-free watch.
 *
 * The previous tool carried a `command`/`tailCommand` payload. Such a watch
 * cannot be restored: its payload no longer exists, and re-arming the record as
 * a timer would silently watch the wrong thing.
 *
 * @param details - Start details read from the session branch.
 * @returns `true` when the entry uses the legacy payload fields.
 */
function isLegacyStart(details: object): boolean {
  return "command" in details || "tailCommand" in details;
}

/**
 * Replay start, stop, and terminal notification entries from a session branch.
 *
 * @param entries - Active session branch entries.
 * @returns Active watch specifications keyed by id.
 */
function collectActiveWatches(
  entries: readonly SessionEntry[],
): Map<string, WatchSpec> {
  const active = new Map<string, WatchSpec>();

  for (const entry of entries) {
    if (
      entry.type === "message" &&
      entry.message.role === "toolResult" &&
      entry.message.toolName === "watch"
    ) {
      const details = entry.message.details as WatchDetails | undefined;
      if (details?.action === "start") {
        if (isLegacyStart(details)) {
          continue;
        }
        const { action: _action, ...spec } = details;
        active.set(spec.id, spec);
      }
      if (details?.action === "stop") {
        active.delete(details.id);
      }
      continue;
    }

    if (entry.type === "custom_message" && entry.customType === NOTICE_TYPE) {
      const details = entry.details as WatchNoticeDetails | undefined;
      if (details?.id && details.state !== "tick") {
        active.delete(details.id);
      }
    }
  }

  return active;
}

/**
 * Registry of background watches for one extension load.
 *
 * Owns the active-watch map and the poll loops, so the tool and session
 * handlers never touch watch bookkeeping directly.
 */
class WatchRegistry {
  private pi: ExtensionAPI;
  private watches: Map<string, Watch>;

  /**
   * @param pi - Extension API used for command execution and notifications.
   */
  constructor(pi: ExtensionAPI) {
    this.pi = pi;
    this.watches = new Map();
  }

  /**
   * Arm a watch and start polling it in the background.
   *
   * @param params - Validated tool input for `action=start`.
   * @returns The persisted specification of the new watch.
   */
  start(params: WatchInput): WatchSpec {
    const id = requireId(params.id, "start");
    if (this.watches.has(id)) {
      throw new Error(
        `Watch "${id}" is already active; stop it first or pick another id.`,
      );
    }

    const condition = params.condition?.trim() || undefined;
    const watch: Watch = {
      id,
      condition,
      intervalSec: params.intervalSec ?? DEFAULT_INTERVAL_SEC,
      maxTicks: params.maxTicks,
      timeoutSec: params.timeoutSec ?? DEFAULT_TIMEOUT_SEC,
      startedAt: Date.now(),
      ticksSent: 0,
      noticePending: false,
      stopped: false,
      controller: new AbortController(),
    };

    this.validateBudget(watch);
    this.arm(watch);
    return toWatchSpec(watch);
  }

  /**
   * Reject budgets that can never pay out.
   *
   * A timer with no ticks could never wake the agent, and a tick scheduled
   * after the deadline would silently never fire.
   *
   * @param watch - Watch about to be armed.
   */
  private validateBudget(watch: Watch): void {
    if (!watch.condition && watch.maxTicks === 0) {
      throw new Error(
        `Watch "${watch.id}" has no condition and maxTicks 0, so it could never wake you.`,
      );
    }

    if (this.canTick(watch) && watch.timeoutSec < watch.intervalSec) {
      throw new Error(
        `Watch "${watch.id}" cannot tick: timeoutSec ${watch.timeoutSec} is shorter than intervalSec ${watch.intervalSec}.`,
      );
    }
  }

  /**
   * Cancel one watch and stop its poll loop.
   *
   * @param id - Id of the watch to cancel.
   * @returns `true` when an active watch had that id.
   */
  stop(id: string): boolean {
    const watch = this.watches.get(id);
    if (!watch) {
      return false;
    }

    watch.stopped = true;
    watch.controller.abort();
    this.watches.delete(id);
    return true;
  }

  /** Cancel every active watch. */
  stopAll(): void {
    for (const watch of this.watches.values()) {
      watch.stopped = true;
      watch.controller.abort();
    }
    this.watches.clear();
  }

  /** Forget which watches still have a queued notification. */
  clearPending(): void {
    for (const watch of this.watches.values()) {
      watch.noticePending = false;
    }
  }

  /**
   * Describe every active watch, one line each.
   *
   * @returns Lines sorted by id, or a message when nothing is active.
   */
  list(): string {
    if (this.watches.size === 0) {
      return "No active watches.";
    }

    return [...this.watches.values()]
      .sort((left, right) => left.id.localeCompare(right.id))
      .map((watch) => this.describe(watch))
      .join("\n");
  }

  /**
   * Describe one active watch.
   *
   * @param id - Id from the tool input.
   * @returns The one-line description of that watch.
   */
  status(id: string): string {
    return this.describe(this.requireActive(id));
  }

  /**
   * Look up an active watch or fail with the list of valid ids.
   *
   * @param id - Id from the tool input.
   * @returns The active watch.
   */
  requireActive(id: string): Watch {
    const watch = this.watches.get(id);
    if (watch) {
      return watch;
    }

    const active = [...this.watches.keys()].sort();
    throw new Error(
      active.length === 0
        ? `No watch "${id}"; nothing is active.`
        : `No watch "${id}"; active: ${active.join(", ")}.`,
    );
  }

  /**
   * Describe one watch as a single line.
   *
   * @param watch - Watch to describe.
   * @returns Id, state, age, tick budget, and condition.
   */
  private describe(watch: Watch): string {
    const ticks =
      watch.maxTicks === undefined
        ? `${watch.ticksSent}/unlimited`
        : `${watch.ticksSent}/${watch.maxTicks}`;
    const target = watch.condition
      ? `cond: ${watch.condition}`
      : "timer, no condition";
    return `${watch.id}  running  ${elapsed(watch)}  ticks ${ticks}  ${target}`;
  }

  /**
   * Replace the current watches with those recorded on a session branch.
   *
   * In-flight loops are cancelled first, so a branch switch cannot leave
   * orphaned pollers that keep notifying about an abandoned timeline.
   *
   * @param entries - Active session branch entries.
   */
  restore(entries: readonly SessionEntry[]): void {
    this.stopAll();

    for (const spec of collectActiveWatches(entries).values()) {
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
   * Register a watch and start its poll loop without blocking the caller.
   *
   * @param watch - Watch to arm.
   */
  private arm(watch: Watch): void {
    this.watches.set(watch.id, watch);
    void this.poll(watch)
      .catch((error) => {
        if (!watch.stopped) {
          this.notify(watch, "error", `error: ${String(error)}`);
        }
      })
      .finally(() => {
        // Ownership check:
        // `restore()` aborts old loops and immediately re-arms the same ids.
        // An old loop may finish after its replacement is in the map; deleting
        // by id alone would orphan the replacement watch, making it impossible
        // to stop. Only remove the entry if this loop still owns it.
        if (this.watches.get(watch.id) === watch) {
          this.watches.delete(watch.id);
        }
      });
  }

  /**
   * Whether the watch may still send a tick.
   *
   * @param watch - Watch to check.
   * @returns `true` when the tick budget is not exhausted.
   */
  private canTick(watch: Watch): boolean {
    return watch.maxTicks === undefined || watch.ticksSent < watch.maxTicks;
  }

  /**
   * Poll a watch until it succeeds, times out, or is cancelled.
   *
   * A condition watch checks once immediately, then on every tick. A timer
   * only ticks, and ends once its budget is spent because it has nothing left
   * to report.
   *
   * @param watch - Watch to run.
   */
  private async poll(watch: Watch): Promise<void> {
    const deadline = watch.startedAt + watch.timeoutSec * 1000;

    if (
      watch.condition &&
      (await this.matches(watch, watch.condition, deadline))
    ) {
      this.finish(watch, "done");
      return;
    }

    while (!watch.stopped) {
      const waitMs = Math.min(watch.intervalSec * 1000, deadline - Date.now());
      if (waitMs > 0) {
        await sleep(waitMs, undefined, { signal: watch.controller.signal });
      }
      if (watch.stopped) {
        return;
      }

      if (Date.now() >= deadline) {
        this.finish(watch, "timeout");
        return;
      }

      if (
        watch.condition &&
        (await this.matches(watch, watch.condition, deadline))
      ) {
        this.finish(watch, "done");
        return;
      }

      if (this.canTick(watch)) {
        this.tick(watch);
        if (!watch.condition && !this.canTick(watch)) {
          // A timer with a spent budget has nothing left to say.
          return;
        }
      }
    }
  }

  /**
   * Run the watch's condition.
   *
   * @param watch - Watch the condition belongs to.
   * @param condition - Shell predicate to evaluate.
   * @param deadline - Unix timestamp in milliseconds when the watch expires.
   * @returns `true` when the condition exited 0.
   */
  private async matches(
    watch: Watch,
    condition: string,
    deadline: number,
  ): Promise<boolean> {
    const remaining = deadline - Date.now();
    const result = await this.pi.exec("bash", ["-lc", condition], {
      signal: watch.controller.signal,
      timeout: Math.min(
        MAX_CONDITION_TIMEOUT_MS,
        Math.max(MIN_CONDITION_TIMEOUT_MS, remaining),
      ),
    });
    return result.code === 0;
  }

  /**
   * Send one tick unless a previous notification is still queued.
   *
   * Dropping the tick instead of queueing a second one keeps a busy agent from
   * waking to a burst of stale ticks; the budget only counts what was sent.
   *
   * @param watch - Watch to tick.
   * @returns `true` when the tick was sent.
   */
  private tick(watch: Watch): boolean {
    if (watch.noticePending) {
      return false;
    }

    watch.ticksSent += 1;
    this.notify(
      watch,
      "tick",
      `tick ${watch.ticksSent}${watch.maxTicks === undefined ? "" : `/${watch.maxTicks}`}, ${elapsed(watch)} elapsed`,
    );
    return true;
  }

  /**
   * Send the final notification of a watch and retire it.
   *
   * @param watch - Watch that finished.
   * @param state - Why it finished.
   */
  private finish(watch: Watch, state: "done" | "timeout"): void {
    if (state === "done") {
      this.notify(
        watch,
        "done",
        `condition met after ${elapsed(watch)}: ${watch.condition}`,
      );
      return;
    }
    this.notify(watch, "timeout", `timeout after ${watch.timeoutSec}s`);
  }

  /**
   * Deliver a watch update to the agent.
   *
   * Uses `steer` so the wake is delivered before the next model request, even
   * mid-turn; when idle it starts a new turn.
   *
   * @param watch - Watch that produced the update.
   * @param state - Notification kind.
   * @param line - One-line body with the watch name and the news.
   */
  private notify(watch: Watch, state: WatchState, line: string): void {
    watch.noticePending = true;
    this.pi.sendMessage(
      {
        customType: NOTICE_TYPE,
        content: `[watch ${watch.id}] ${line}`,
        display: true,
        details: { id: watch.id, state },
      },
      { triggerTurn: true, deliverAs: "steer" },
    );
  }
}

/**
 * Describe what a freshly armed watch will do.
 *
 * @param spec - Specification returned by the registry.
 * @returns One-line summary for the tool result.
 */
function describeStart(spec: WatchSpec): string {
  const ticks =
    spec.maxTicks === undefined
      ? `tick every ${spec.intervalSec}s`
      : spec.maxTicks === 0
        ? "no ticks"
        : spec.maxTicks === 1
          ? `one tick after ${spec.intervalSec}s`
          : `tick every ${spec.intervalSec}s, at most ${spec.maxTicks}`;
  const ending = spec.condition
    ? `ends when the condition first exits 0 or after ${spec.timeoutSec}s`
    : `then ends (timeout ${spec.timeoutSec}s)`;
  return `Armed "${spec.id}": ${ticks}; ${ending}. Wakes arrive even after you end your turn.`;
}

/**
 * Build the `watch` tool definition.
 *
 * @param registry - Watch registry shared with the session handlers.
 * @returns Tool definition registered with Pi.
 */
function createWatchTool(registry: WatchRegistry) {
  return {
    name: "watch",
    label: "Watch",
    description:
      "Manage named background watches. action=start polls an optional shell condition on a fixed cadence and wakes you with a short notification (a tick, 'condition met', or 'timeout'); it returns immediately. action=stop cancels a watch. action=status reports one watch or all of them. Wakes carry no log text on purpose: read the job's output yourself after a wake, so a queued wake can never be stale.",
    promptSnippet:
      "Watch a job, log, or process in the background and wake the agent on a tick or when a condition is met",
    promptGuidelines: [
      "Name every watch with a short, unique, purpose-bearing id (batch3-done, pa1-peek, log1-monitor, etc.): the id is what you see in every wake, so it must remind you what you are waiting for.",
      "Use watch instead of `sleep N; ...` in bash. Arm the watch, then keep working or end your turn; ending a turn loses nothing because the wake starts a new turn when you are idle.",
      "For a single deferred look, use no condition with intervalSec=N and maxTicks=1: one wake after N seconds, then the watch ends.",
      "For 'tell me when it finishes', give a condition with maxTicks=0: no ticks, one wake when the condition exits 0.",
      "A wake says only that something happened. After a wake, run the check you actually need, then stop the watch once you no longer care.",
    ],
    parameters: WatchParams,

    /**
     * Start, stop, or inspect a watch.
     *
     * @param _toolCallId - Tool call id assigned by Pi.
     * @param params - Action plus its arguments.
     * @returns Tool result describing the outcome.
     */
    async execute(_toolCallId: string, params: WatchInput) {
      switch (params.action) {
        case "stop": {
          const id = requireId(params.id, "stop");
          registry.requireActive(id);
          registry.stop(id);
          return watchResult(`Stopped "${id}".`, { action: "stop", id });
        }

        case "status": {
          if (!params.id) {
            return watchResult(registry.list(), { action: "status" });
          }
          const id = requireId(params.id, "status");
          return watchResult(registry.status(id), { action: "status", id });
        }

        case "start": {
          const spec = registry.start(params);
          return watchResult(describeStart(spec), { action: "start", ...spec });
        }

        default:
          throw new Error(`Unknown action: ${params.action}`);
      }
    },
  };
}

/**
 * Register the watch extension with Pi.
 *
 * @param pi - Extension API used to register the tool and session cleanup.
 */
export default function watch(pi: ExtensionAPI): void {
  const registry = new WatchRegistry(pi);

  pi.registerTool(createWatchTool(registry));

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
