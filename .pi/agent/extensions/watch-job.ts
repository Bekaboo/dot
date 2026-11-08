/**
 * Background job watcher.
 *
 * `watch_job` arms a poll loop and returns immediately, so the agent can keep
 * working or talking. When the condition succeeds, the watch times out, or the
 * report interval elapses, the agent receives a follow-up message that
 * triggers a new turn.
 */

import { setTimeout as sleep } from "node:timers/promises";

import type {
  ExtensionAPI,
  SessionEntry,
} from "@earendil-works/pi-coding-agent";

import { type Static, Type } from "typebox";

// Watch duration, polling, and notification defaults, in seconds.
const DEFAULT_TIMEOUT_SEC = 3_600;
const MIN_TIMEOUT_SEC = 10;

const DEFAULT_INTERVAL_SEC = 60;
const MIN_INTERVAL_SEC = 1;

// Command execution deadlines, in milliseconds.
const TAIL_TIMEOUT_MS = 10_000;
const MIN_CONDITION_TIMEOUT_MS = 1_000;
const MAX_CONDITION_TIMEOUT_MS = 30_000;

/** Schema for the `watch_job` tool. */
const WatchJobParams = Type.Object({
  command: Type.String({
    description: "Shell condition. Exit code 0 means the job finished.",
  }),
  tailCommand: Type.Optional(
    Type.String({
      description:
        "Optional command to capture context, e.g. tail -n 60 /tmp/job.log.",
    }),
  ),
  timeoutSec: Type.Optional(
    Type.Number({
      description: "Maximum watch duration in seconds.",
      minimum: MIN_TIMEOUT_SEC,
      default: DEFAULT_TIMEOUT_SEC,
    }),
  ),
  intervalSec: Type.Optional(
    Type.Number({
      description:
        "Interval in seconds between condition checks. A check that finds the job still running also sends a progress notification when tailCommand is set, so set this to the cadence the user asked for.",
      minimum: MIN_INTERVAL_SEC,
      default: DEFAULT_INTERVAL_SEC,
    }),
  ),
});

/** Schema for the `watch_stop` tool. */
const WatchStopParams = Type.Object({
  id: Type.String({ description: "Watch id returned by watch_job." }),
});

/** Input accepted by the `watch_job` tool. */
type WatchJobInput = Static<typeof WatchJobParams>;

/** Input accepted by the `watch_stop` tool. */
type WatchStopInput = Static<typeof WatchStopParams>;

/** Outcome reported by a watch notification. */
type WatchState = "running" | "done" | "timeout" | "error";

/** Persisted specification of one watch. */
interface WatchSpec {
  /** Stable id returned to the model and accepted by `watch_stop`. */
  id: string;
  /** Shell condition; exit code 0 ends the watch successfully. */
  command: string;
  /** Optional command whose output is included in notifications. */
  tailCommand?: string;
  /** Maximum lifetime in seconds. */
  timeoutSec: number;
  /** Interval between condition checks and progress reports, in seconds. */
  intervalSec: number;
  /** Unix timestamp in milliseconds when the watch was armed. */
  startedAt: number;
}

/** One active background watch. */
interface Watch extends WatchSpec {
  /** Set when the user or session teardown cancels the watch. */
  stopped: boolean;
  /** Aborts in-flight `pi.exec()` and sleep calls on cancellation. */
  controller: AbortController;
}

/** Details stored on a `watch_stop` tool result. */
interface WatchStopDetails {
  /** Id of the watch the result applies to. */
  id: string;
}

/** Details stored on a `job-watch` notification. */
interface WatchNoticeDetails {
  /** Watch id that produced the notification. */
  id: string;
  /** Notification state. */
  state: WatchState;
}

/**
 * Extract the persisted fields from a watch.
 *
 * @param watch - Watch to serialize into tool-result details.
 * @returns The watch specification stored in the session branch.
 */
function toWatchSpec(watch: Watch): WatchSpec {
  return {
    id: watch.id,
    command: watch.command,
    tailCommand: watch.tailCommand,
    timeoutSec: watch.timeoutSec,
    intervalSec: watch.intervalSec,
    startedAt: watch.startedAt,
  };
}

/**
 * Replay watch, stop, and terminal notification entries from a session branch.
 *
 * @param entries - Active session branch entries.
 * @returns Active watch specifications keyed by id.
 */
function collectActiveWatches(
  entries: readonly SessionEntry[],
): Map<string, WatchSpec> {
  const active = new Map<string, WatchSpec>();

  for (const entry of entries) {
    if (entry.type === "message" && entry.message.role === "toolResult") {
      const message = entry.message;
      if (message.toolName === "watch_job") {
        const details = message.details as WatchSpec | undefined;
        if (details) {
          active.set(details.id, details);
        }
        continue;
      }
      if (message.toolName === "watch_stop") {
        const details = message.details as WatchStopDetails | undefined;
        if (details?.id) {
          active.delete(details.id);
        }
        continue;
      }
    }

    if (entry.type === "custom_message" && entry.customType === "job-watch") {
      const details = entry.details as WatchNoticeDetails | undefined;
      if (details?.id && details.state !== "running") {
        active.delete(details.id);
      }
    }
  }

  return active;
}

/**
 * Choose the next numeric watch id after restoring a branch.
 *
 * @param active - Restored watches keyed by id.
 * @returns A counter that does not collide with restored ids.
 */
function nextWatchId(active: Map<string, WatchSpec>): number {
  let next = 1;
  for (const id of active.keys()) {
    const suffix = Number(id.startsWith("job-") ? id.slice("job-".length) : "");
    if (Number.isInteger(suffix)) {
      next = Math.max(next, suffix + 1);
    }
  }
  return next;
}

/**
 * Registry of background watches for one extension load.
 *
 * Owns the id counter, the active-watch map, and the poll loops, so tools and
 * session handlers never touch watch bookkeeping directly.
 */
class WatchRegistry {
  private pi: ExtensionAPI;
  private watches: Map<string, Watch>;
  private nextId: number;

  /**
   * @param pi - Extension API used for command execution and notifications.
   */
  constructor(pi: ExtensionAPI) {
    this.pi = pi;
    this.watches = new Map();
    this.nextId = 1;
  }

  /**
   * Arm a watch and start polling it in the background.
   *
   * @param params - Validated `watch_job` input.
   * @returns The persisted specification of the new watch.
   */
  start(params: WatchJobInput): WatchSpec {
    const watch: Watch = {
      id: `job-${this.nextId++}`,
      command: params.command,
      tailCommand: params.tailCommand,
      timeoutSec: params.timeoutSec ?? DEFAULT_TIMEOUT_SEC,
      intervalSec: params.intervalSec ?? DEFAULT_INTERVAL_SEC,
      startedAt: Date.now(),
      stopped: false,
      controller: new AbortController(),
    };

    this.arm(watch);
    return toWatchSpec(watch);
  }

  /**
   * Cancel one watch and stop its poll loop.
   *
   * @param id - Id of the watch to stop.
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

    const active = collectActiveWatches(entries);
    this.nextId = nextWatchId(active);
    for (const spec of active.values()) {
      this.arm({
        ...spec,
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
          this.notify(watch, "error", String(error));
        }
      })
      .finally(() => {
        this.watches.delete(watch.id);
      });
  }

  /**
   * Poll a watch until it succeeds, times out, or is cancelled.
   *
   * @param watch - Watch to run.
   */
  private async poll(watch: Watch): Promise<void> {
    const deadline = watch.startedAt + watch.timeoutSec * 1000;
    const intervalMs = watch.intervalSec * 1000;
    let lastReport = watch.startedAt;

    while (Date.now() < deadline) {
      const remaining = deadline - Date.now();
      const result = await this.pi.exec("bash", ["-lc", watch.command], {
        signal: watch.controller.signal,
        timeout: Math.min(
          MAX_CONDITION_TIMEOUT_MS,
          Math.max(MIN_CONDITION_TIMEOUT_MS, remaining),
        ),
      });

      if (result.code === 0) {
        this.notify(
          watch,
          "done",
          (await this.readTail(watch)) || "Condition met.",
        );
        return;
      }

      // A progress ping only adds information when it carries a new snapshot,
      // so a watch without tailCommand stays silent until it finishes. The
      // gate also skips the instant check made right after arming.
      if (watch.tailCommand && Date.now() - lastReport >= intervalMs) {
        lastReport = Date.now();
        this.notify(
          watch,
          "running",
          (await this.readTail(watch)) || "Still running.",
        );
      }

      const waitMs = Math.min(intervalMs, deadline - Date.now());
      if (waitMs <= 0) {
        break;
      }
      await sleep(waitMs, undefined, { signal: watch.controller.signal });
    }

    this.notify(
      watch,
      "timeout",
      (await this.readTail(watch)) || `No result after ${watch.timeoutSec}s.`,
    );
  }

  /**
   * Read the optional context command for a watch.
   *
   * @param watch - Watch whose tail command should run.
   * @returns Combined stdout and stderr, trimmed; empty when no command is set.
   */
  private async readTail(watch: Watch): Promise<string> {
    if (!watch.tailCommand) {
      return "";
    }

    const result = await this.pi.exec("bash", ["-lc", watch.tailCommand], {
      signal: watch.controller.signal,
      timeout: TAIL_TIMEOUT_MS,
    });
    return `${result.stdout}${result.stderr}`.trim();
  }

  /**
   * Deliver a watch update to the agent.
   *
   * Uses `followUp` so the notification waits for the current run to finish and
   * starts a new turn when the agent is idle.
   *
   * @param watch - Watch that produced the update.
   * @param state - Current watch outcome.
   * @param detail - Log tail or explanatory text for the message body.
   */
  private notify(watch: Watch, state: WatchState, detail: string): void {
    this.pi.sendMessage(
      {
        customType: "job-watch",
        content: `[job-watch ${watch.id}] ${state}\n\n${detail}`.trim(),
        display: true,
        details: { id: watch.id, state },
      },
      { triggerTurn: true, deliverAs: "followUp" },
    );
  }
}

/**
 * Build the `watch_job` tool definition.
 *
 * @param registry - Watch registry shared with the session handlers.
 * @returns Tool definition registered with Pi.
 */
function createWatchJobTool(registry: WatchRegistry) {
  return {
    name: "watch_job",
    label: "Watch job",
    description:
      "Arm a background watcher that polls a shell condition and notifies the agent when the condition succeeds, times out, or on a progress interval. Returns immediately. This is the default way to wait for anything slow: it replaces blocking waits, sleep loops, and repeated manual polling.",
    promptSnippet:
      "Watch a slow command, file, log, or process in the background and report when it changes or finishes",
    promptGuidelines: [
      "Use watch_job instead of a blocking bash wait, a sleep loop, or repeated manual polling whenever a command, build, test, download, or monitor may run longer than a few seconds.",
      "Use watch_job when the user asks to monitor a file, log, process, or job and report how it changes over time: set intervalSec to the requested reporting cadence and give tailCommand a command that prints a fresh snapshot each time.",
      "After starting any long-running job with bash, arm watch_job immediately and then keep working or answer the user; do not hold the turn with a blocking wait.",
      "Use watch_stop only when the watched condition is no longer relevant or the user asks you to stop watching.",
    ],
    parameters: WatchJobParams,

    /**
     * Start a watch and return immediately with its id.
     *
     * @param _toolCallId - Tool call id assigned by Pi.
     * @param params - Watch condition, timing, and optional tail command.
     * @returns Tool result describing the background watch.
     */
    async execute(_toolCallId: string, params: WatchJobInput) {
      const spec = registry.start(params);
      return {
        content: [
          {
            type: "text" as const,
            text: `Watching ${spec.id} in the background. Continue with other work; the agent will be notified when the condition succeeds or the watch times out.`,
          },
        ],
        details: spec,
      };
    },
  };
}

/**
 * Build the `watch_stop` tool definition.
 *
 * @param registry - Watch registry shared with the session handlers.
 * @returns Tool definition registered with Pi.
 */
function createWatchStopTool(registry: WatchRegistry) {
  return {
    name: "watch_stop",
    label: "Stop watch",
    description: "Stop an active background job watcher.",
    parameters: WatchStopParams,

    /**
     * Stop one watch by id.
     *
     * @param _toolCallId - Tool call id assigned by Pi.
     * @param params - Id of the watch to stop.
     * @returns Tool result indicating whether the watch was stopped.
     */
    async execute(_toolCallId: string, params: WatchStopInput) {
      if (!registry.stop(params.id)) {
        return {
          content: [
            {
              type: "text" as const,
              text: `No active watch: ${params.id}`,
            },
          ],
          details: { id: params.id },
        };
      }

      return {
        content: [{ type: "text" as const, text: `Stopped ${params.id}.` }],
        details: { id: params.id },
      };
    },
  };
}

/**
 * Register the job-watch extension with Pi.
 *
 * @param pi - Extension API used to register tools and session cleanup.
 */
export default function watchJob(pi: ExtensionAPI): void {
  const registry = new WatchRegistry(pi);

  pi.registerTool(createWatchJobTool(registry));
  pi.registerTool(createWatchStopTool(registry));

  pi.on("session_start", async (_event, ctx) => {
    registry.restore(ctx.sessionManager.getBranch());
  });

  pi.on("session_tree", async (_event, ctx) => {
    registry.restore(ctx.sessionManager.getBranch());
  });

  pi.on("session_shutdown", async () => registry.stopAll());
}
