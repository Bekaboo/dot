/**
 * All the things related to async and periodic jobs.
 *
 * Background timer tools: `timer_start`, `timer_stop`, `timer_status`.
 *
 * A timer is one of three things, told apart by what ends it:
 *
 * - A background command that ends when the process exits (`start`)
 * - A poller that ends when a shell predicate exits 0 (`condition`)
 * - A periodic job that ends only on `timer_stop`
 *
 * Its tick budget, or its deadline. Every ending wakes the agent with a short
 * notification. Timers are named by the agent, so every wake and the status
 * list are self-describing. The user-facing `/timers` command shows the
 * session's timers as an aligned table: the running ones first, then the ones
 * that ended, each with the same state marker the `/subagents` view uses. The
 * order is fixed when the view opens and does not follow state changes after
 * that, so no row moves under the reader. Enter opens one timer's detail: what
 * it runs or waits for, its deadlines, and the tail of the job log it writes.
 */

import { type ChildProcess, spawn } from "node:child_process";
import {
  appendFileSync,
  closeSync,
  existsSync,
  fstatSync,
  mkdirSync,
  openSync,
  readSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import {
  type AgentToolUpdateCallback,
  type ExtensionAPI,
  type ExtensionCommandContext,
  type ExtensionToolContext,
  getAgentDir,
  type KeybindingsManager,
  type SessionEntry,
  type Theme,
  type ToolDefinition,
} from "@earendil-works/pi-coding-agent";

import {
  type Component,
  type TUI,
  truncateToWidth,
  visibleWidth,
} from "@earendil-works/pi-tui";

import { type Static, Type } from "typebox";

import {
  DrillDown,
  OverlayPage,
  padRight,
  SELECTED_CURSOR,
} from "./utils/overlay.ts";
import { PAGE_PADDING_X, windowStart } from "./utils/page.ts";
import { type RunState, Spinner } from "./utils/spinner.ts";

export {
  DEFAULT_JOB_TIMEOUT_SEC,
  DEFAULT_TIMEOUT_SEC,
  JOB_TAIL_LINES,
  ON_TICK_MAX_LINES,
  RETIRED_HISTORY,
  SELECTED_CURSOR,
};

// Timer duration, polling, and notification defaults, in seconds.
const DEFAULT_TIMEOUT_SEC = 3_600;
const MIN_TIMEOUT_SEC = 1;

// A job often runs for hours, so its own default deadline is a day.
const DEFAULT_JOB_TIMEOUT_SEC = 86_400;

const DEFAULT_INTERVAL_SEC = 60;
const MIN_INTERVAL_SEC = 1;

// How long a job gets between SIGTERM and SIGKILL, in milliseconds.
const KILL_GRACE_MS = 5_000;

// Largest delay `setTimeout` honors; anything above it fires immediately.
const MAX_TIMEOUT_MS = 2 ** 31 - 1;

// Job logs live under the agent dir, one file per run.
const JOB_LOG_DIR = "jobs";

// A wake carries only the end of the log: read from the end, then keep a few
// lines, so a log that grew for hours cannot flood the model.
const LOG_TAIL_BYTES = 64 * 1024;
const JOB_TAIL_LINES = 10;
const JOB_TAIL_CHARS = 2_000;

// The `/timers` detail view reads the same bounded window, but keeps more of
// it: a reader who asked for the detail can scroll back through recent output.
const DETAIL_TAIL_LINES = 200;

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
 * by status, and names the job log file.
 */
const ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{2,39}$/;

/** Custom message type used for timer notifications. */
const NOTICE_TYPE = "timer";

/**
 * How many ended timers are remembered, for `/timers`, `timer_status` and a
 * late `timer_stop` reply.
 */
const RETIRED_HISTORY = 10;

/** Names that replay as timer start results, including the old combined tool. */
const START_TOOL_NAMES = new Set(["timer_start", "timer"]);

/** Names that replay as timer stop results, including the old combined tool. */
const STOP_TOOL_NAMES = new Set(["timer_stop", "timer"]);

/** Schema for the `timer_start` tool. */
const TimerStartParams = Type.Object({
  id: Type.String({
    description:
      "Timer name: short, unique, purpose-bearing, e.g. batch3-done or pa1-peek. It appears in every wake and in `timer_status`, and it names the job log.",
  }),
  start: Type.Optional(
    Type.String({
      description:
        "Shell command to run in the background and log; the timer ends when the process exits, and the wake carries its exit code and log tail. Mutually exclusive with `condition`.",
    }),
  ),
  condition: Type.Optional(
    Type.String({
      description:
        "Shell predicate checked immediately and at each tick; exit code 0 ends the timer and wakes you with 'condition met'. Mutually exclusive with `start`.",
    }),
  ),
  onTick: Type.Optional(
    Type.String({
      description:
        "Shell command run on every tick, including the one that ends a periodic timer; its output rides along with the wake. Never block or sleep. With `start` it also runs once at exit, after the log tail.",
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
        "Maximum tick wakes. 0 disables ticks and is the default with `start`; periodic mode needs at least 1. The final exit, condition, and timeout wakes do not count.",
      minimum: 0,
    }),
  ),
  timeoutSec: Type.Optional(
    Type.Number({
      description:
        "Lifetime cap in seconds; expiry kills a `start` job. Default 3600, or 86400 with `start`.",
      minimum: MIN_TIMEOUT_SEC,
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
type TimerState = "tick" | "done" | "timeout" | "failed" | "killed";

/** Persisted specification of one timer. */
interface TimerSpec {
  /** Agent-chosen name, unique among active timers. */
  id: string;
  /** Shell command run in the background; the timer ends when it exits. */
  start?: string;
  /** Absolute path of the job log; set with `start`. */
  logPath?: string;
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

/** How a background job ended. */
interface JobOutcome {
  /** Exit code, or `null` when a signal ended it. */
  code: number | null;
  /** Signal that ended it, if any. */
  signal: NodeJS.Signals | null;
  /** Spawn failure, when the command never ran. */
  error?: string;
}

/** A background command owned by one timer. */
interface Job {
  id: string;
  /** Absolute path of the log the job writes to. */
  logPath: string;
  /** Unix timestamp in milliseconds when the job was spawned. */
  startedAt: number;
  proc: ChildProcess;
  /** Resolves once the process exited or failed to spawn. */
  done: Promise<JobOutcome>;
}

/** One active timer. */
interface Timer extends TimerSpec {
  /** Ticks actually delivered. */
  ticksSent: number;
  /** A notification is queued and not yet acted on by the agent. */
  noticePending: boolean;
  /** Set when the user or session teardown cancels the timer. */
  stopped: boolean;
  /** The final wake was already sent, so nothing else may finish this timer. */
  settled: boolean;
  /** Background job this timer watches, when it was started with `start`. */
  job?: Job;
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
 * @param startedAt - Unix timestamp in milliseconds when the timer was armed.
 * @returns Whole seconds, e.g. `40s`.
 */
function elapsed(startedAt: number): string {
  return `${Math.floor((Date.now() - startedAt) / 1000)}s`;
}

/** One timer as fields, so display code can align them into columns. */
interface TimerRow {
  id: string;
  /** Whether the timer still runs, or how it ended. */
  state: RunState;
  age: string;
  ticks: string;
  target: string;
  /** Specification it was armed with, which its detail view shows. */
  spec: TimerSpec;
  /** Why an ended timer finished; absent while it runs. */
  reason?: string;
  /** Process id of the job, while this process still watches it. */
  pid?: number;
}

/** Columns of a timer table, in display order. */
const TIMER_COLUMNS = ["id", "state", "age", "ticks", "target"] as const;

/** A column of the timer table. */
type TimerColumn = (typeof TIMER_COLUMNS)[number];

/**
 * Render one timer row on a single line.
 *
 * @param row - Timer fields to join.
 * @returns Fields separated by two spaces.
 */
function formatTimerRow(row: TimerRow): string {
  return TIMER_COLUMNS.map((column) => row[column]).join("  ");
}

/**
 * Order two rows by when their timers were armed.
 *
 * `/timers` groups the running rows above the ended ones, and reads each group
 * oldest first, so a row keeps its place while it runs and a new one lands at
 * the bottom of its group.
 *
 * @param left - Left row.
 * @param right - Right row.
 * @returns Negative when `left` was armed first.
 */
function byStartedAt(left: TimerRow, right: TimerRow): number {
  return left.spec.startedAt - right.spec.startedAt;
}

/** Width of each timer column, in terminal columns. */
type TimerWidths = Record<TimerColumn, number>;

/**
 * Measure the widest value of every timer column, so rows line up.
 *
 * @param rows - Rows the overlay shows.
 * @returns The terminal width of each column.
 */
function timerWidths(rows: readonly TimerRow[]): TimerWidths {
  const widths: TimerWidths = {
    id: 0,
    state: 0,
    age: 0,
    ticks: 0,
    target: 0,
  };
  for (const row of rows) {
    for (const column of TIMER_COLUMNS) {
      widths[column] = Math.max(widths[column], visibleWidth(row[column]));
    }
  }
  return widths;
}

/**
 * Summary line of the `/timers` overlay.
 *
 * @param rows - Rows the overlay shows.
 * @param theme - Active theme.
 * @returns A styled count, or the empty state.
 */
function summaryOf(rows: readonly TimerRow[], theme: Theme): string {
  if (rows.length === 0) {
    return theme.fg("dim", "No timers have run in this session.");
  }
  const running = rows.filter((row) => row.state === "running").length;
  return theme.fg(
    "muted",
    `${running} running, ${rows.length - running} finished`,
  );
}

/**
 * Local wall-clock time of an event, for the detail view.
 *
 * @param ms - Epoch time in ms.
 * @returns Text such as "15:56:43".
 */
function clockTime(ms: number): string {
  return new Date(ms).toTimeString().slice(0, "hh:mm:ss".length);
}

/**
 * Title line of one timer's detail view: its id, state and budget.
 *
 * @param row - Timer the view shows.
 * @param stateMarker - Styled state marker of the timer.
 * @param theme - Active theme.
 * @returns Text naming its id, state marker, state, timeout, interval and tick
 *   budget, in the order the list row shows them.
 */
function detailTitle(row: TimerRow, stateMarker: string, theme: Theme): string {
  const state =
    row.state === "running"
      ? `running for ${row.age}`
      : `${row.state} after ${row.age}`;
  // A job timer with no tick budget runs until its process exits, so neither an
  // interval nor a tick count says anything about it.
  const ticking = row.spec.maxTicks !== 0;
  return [
    theme.bold(row.id),
    stateMarker,
    theme.fg("muted", state),
    theme.fg("dim", `timeout=${row.spec.timeoutSec}s`),
    ticking ? theme.fg("dim", `interval=${row.spec.intervalSec}s`) : undefined,
    ticking && row.state === "running" ? theme.fg("dim", row.ticks) : undefined,
  ]
    .filter((part) => part !== undefined)
    .join(" ");
}

/**
 * What one timer runs, waits for, and where it logs.
 *
 * Only what the timer actually has appears, so a job timer shows no condition
 * and a periodic timer shows no log path.
 *
 * @param row - Timer the view shows.
 * @param theme - Active theme.
 * @returns Comma-separated parts, never empty.
 */
function detailSpec(row: TimerRow, theme: Theme): string {
  const { spec } = row;
  const parts = [theme.fg("dim", `started=${clockTime(spec.startedAt)}`)];
  if (row.pid !== undefined) parts.push(theme.fg("dim", `pid ${row.pid}`));
  if (spec.logPath) parts.push(theme.fg("dim", spec.logPath));
  if (spec.start) parts.push(theme.fg("muted", spec.start));
  if (spec.condition) parts.push(theme.fg("muted", `cond: ${spec.condition}`));
  if (spec.onTick) parts.push(theme.fg("muted", `onTick: ${spec.onTick}`));
  if (row.reason) parts.push(theme.fg("muted", `ended: ${row.reason}`));
  return parts.join(", ");
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
 * Classify how a job ended, for its wake and its `/timers` marker.
 *
 * @param outcome - Exit code, signal, or spawn failure.
 * @returns `killed` for a signal from outside the timer, `done` for exit 0,
 *   and `failed` otherwise.
 */
function jobEndState(outcome: JobOutcome): "done" | "failed" | "killed" {
  if (outcome.error) return "failed";
  if (outcome.signal) return "killed";
  return outcome.code === 0 ? "done" : "failed";
}

/**
 * Name how a job ended, for its wake, its log, and its retirement reason.
 *
 * @param outcome - Exit code, signal, or spawn failure.
 * @param elapsedText - Time since the job started, e.g. `41s`.
 * @returns The wake line, the short reason for `timer_stop`, and the log marker.
 */
function describeJobEnd(
  outcome: JobOutcome,
  elapsedText: string,
): { line: string; reason: string; marker: string } {
  if (outcome.error) {
    return {
      line: `failed to start: ${outcome.error}`,
      reason: "failed to start",
      marker: "",
    };
  }
  if (outcome.signal) {
    return {
      line: `killed by ${outcome.signal} after ${elapsedText}, not by the timer`,
      reason: `killed by ${outcome.signal}`,
      marker: `killed by ${outcome.signal}`,
    };
  }
  return {
    line:
      outcome.code === 0
        ? `exited 0 after ${elapsedText}`
        : `failed: exit ${outcome.code} after ${elapsedText}`,
    reason: outcome.code === 0 ? "exited 0" : `failed: exit ${outcome.code}`,
    marker: `exit ${outcome.code}`,
  };
}

/**
 * Append how a job ended to its log.
 *
 * The log outlives the wake that reported the outcome, so the file has to say
 * it too. A job that failed to spawn has no log to write to, and a log that
 * disappeared is not worth an error.
 *
 * @param path - Absolute path of the job log.
 * @param marker - Short status, e.g. `exit 0` or `killed by the timer`.
 */
function appendLogMarker(path: string, marker: string): void {
  if (!marker || !existsSync(path)) {
    return;
  }
  try {
    appendFileSync(path, `[${marker}]\n`);
  } catch {
    // Nothing to add if the log is gone.
  }
}

/**
 * Read the end of a job log.
 *
 * Reads a bounded window from the end, so a log that grew for hours costs the
 * same as a short one.
 *
 * @param path - Absolute path of the job log.
 * @param maxLines - Trailing lines to keep.
 * @param maxChars - Character budget for the kept lines.
 * @returns At most `maxLines` lines and `maxChars` characters.
 */
function readLogTail(
  path: string,
  maxLines = JOB_TAIL_LINES,
  maxChars = JOB_TAIL_CHARS,
): string {
  let fd: number | undefined;
  try {
    fd = openSync(path, "r");
    const size = fstatSync(fd).size;
    const length = Math.min(size, LOG_TAIL_BYTES);
    const buffer = Buffer.alloc(length);
    const bytesRead = readSync(fd, buffer, 0, length, size - length);
    // Dropping from the window start: the first line of a partial window is a
    // fragment, and cutting mid-character would leave a broken code point.
    const text = buffer.subarray(0, bytesRead).toString("utf8");
    const window = size > length ? text.slice(text.indexOf("\n") + 1) : text;
    // A progress bar redraws one line with `\r`; keep only the final state.
    const tail = window
      .trimEnd()
      .split("\n")
      .map((line) => line.slice(line.lastIndexOf("\r") + 1))
      .slice(-maxLines)
      .join("\n");
    return tail.length > maxChars
      ? `...${tail.slice(tail.length - maxChars)}`
      : tail;
  } catch {
    // A job that failed to spawn has no log yet; the outcome already says why.
    return "";
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

/**
 * Spawn a job with its output going to `logPath`.
 *
 * `-c` rather than `-lc`, matching the built-in bash tool: a login shell would
 * print profile noise into the job log. The parent's copy of the log fd is
 * closed even when spawning throws, so the child remains the only writer.
 *
 * @param command - Shell command to run.
 * @param cwd - Directory to run in.
 * @param logPath - File that receives stdout and stderr.
 * @returns The spawned shell, a process-group leader.
 */
function spawnJob(command: string, cwd: string, logPath: string): ChildProcess {
  const log = openSync(logPath, "a");
  try {
    return spawn("bash", ["-c", command], {
      cwd,
      detached: true,
      stdio: ["ignore", log, log],
    });
  } finally {
    closeSync(log);
  }
}

/**
 * Signal a job's whole process group.
 *
 * A job is spawned as its own group leader, so signalling the group reaches
 * the shell and everything it started. A group that already ended is not an
 * error.
 *
 * @param pid - Group leader pid, which is the spawned shell.
 * @param signal - Signal to send to the group.
 */
function signalGroup(pid: number, signal: NodeJS.Signals): void {
  try {
    process.kill(-pid, signal);
  } catch {
    // ESRCH: the group ended between the check and the signal.
  }
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
    start: timer.start,
    logPath: timer.logPath,
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

/** One timer that ended, kept so a late `timer_stop` and `/timers` can report it. */
interface RetiredTimer {
  /** Why it ended, e.g. `tick budget spent`. */
  reason: string;
  /** How it ended, which picks its marker and state word. */
  state: RunState;
  /** Elapsed time at the end, e.g. `41s`. */
  age: string;
  /** Specification it was armed with, so its detail view outlives it. */
  spec: TimerSpec;
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
   * Timers that ended, newest last, with how and when they ended.
   *
   * Kept so a late `timer_stop` reports "stopped" instead of failing with
   * "no such timer": after the wake that announced the end, stopping the
   * timer is the obvious next move, and it must not look like an error. The
   * `/timers` overlay lists the same entries after the active ones, so a timer
   * does not vanish from the view the moment it wakes the agent. Bounded like
   * the subagent history, so a long session of short timers cannot grow it
   * without limit.
   */
  private retired: Map<string, RetiredTimer>;
  /**
   * Jobs this process still watches, keyed by timer id.
   *
   * Jobs belong to the process, not to a session branch: restoring a branch
   * must never spawn or signal one from a pid it finds in the transcript.
   */
  private jobs: Map<string, Job>;

  /**
   * @param pi - Extension API used for command execution and notifications.
   */
  constructor(pi: ExtensionAPI) {
    this.pi = pi;
    this.timers = new Map();
    this.retired = new Map();
    this.jobs = new Map();
  }

  /**
   * Arm a timer and start polling it in the background.
   *
   * @param params - Validated `timer_start` input.
   * @param cwd - Directory the job runs in, which is the session's own cwd.
   * @returns The persisted specification of the new timer.
   */
  start(params: TimerStartInput, cwd: string): TimerSpec {
    const id = requireId(params.id);
    const running = this.jobs.get(id);
    if (running) {
      throw new Error(
        `Timer "${id}" is already active: its job is still running, log ${running.logPath}; stop it or pick another id.`,
      );
    }
    if (this.timers.has(id)) {
      throw new Error(
        `Timer "${id}" is already active; stop it first or pick another id.`,
      );
    }

    const command = params.start?.trim() || undefined;
    const condition = params.condition?.trim() || undefined;
    if (command && condition) {
      throw new Error(
        `Timer "${id}": start and condition are mutually exclusive -- use start to be told when a command exits, condition to wait for a predicate.`,
      );
    }

    const startedAt = Date.now();
    const timer: Timer = {
      id,
      start: command,
      condition,
      onTick: params.onTick?.trim() || undefined,
      intervalSec: params.intervalSec ?? DEFAULT_INTERVAL_SEC,
      maxTicks: params.maxTicks ?? (command ? 0 : undefined),
      timeoutSec:
        params.timeoutSec ??
        (command ? DEFAULT_JOB_TIMEOUT_SEC : DEFAULT_TIMEOUT_SEC),
      startedAt,
      ticksSent: 0,
      noticePending: false,
      stopped: false,
      settled: false,
      controller: new AbortController(),
    };

    this.validateBudget(timer);
    if (command) {
      timer.job = this.launch(id, command, startedAt, cwd);
      timer.logPath = timer.job.logPath;
    }
    this.arm(timer);
    return toTimerSpec(timer);
  }

  /**
   * Start a command as its own process group, with its output going to a log.
   *
   * The child is detached into its own group so `timer_stop`, a timeout, or
   * session shutdown can signal the whole job, and so the log fd replaces the
   * pipes that would otherwise make the exit wait on grandchildren.
   *
   * @param id - Timer id, which names the log.
   * @param command - Shell command to run.
   * @param startedAt - Spawn time, part of the log name.
   * @param cwd - Directory to run in.
   * @returns The job this timer now watches.
   */
  private launch(
    id: string,
    command: string,
    startedAt: number,
    cwd: string,
  ): Job {
    const logPath = join(getAgentDir(), JOB_LOG_DIR, `${id}-${startedAt}.log`);
    mkdirSync(dirname(logPath), { recursive: true });
    const proc = spawnJob(command, cwd, logPath);

    const done = new Promise<JobOutcome>((resolve) => {
      proc.once("exit", (code, signal) => resolve({ code, signal }));
      proc.once("error", (error) =>
        resolve({ code: null, signal: null, error: String(error) }),
      );
    });
    const job: Job = { id, logPath, startedAt, proc, done };
    this.jobs.set(id, job);
    // A job can lose its timer when a branch is restored without it. Drop the
    // entry once it exits, so the id is reusable and nothing leaks.
    void done.then(() => {
      if (this.jobs.get(id) === job) {
        this.jobs.delete(id);
      }
    });
    return job;
  }

  /**
   * Stop a job: stop, expiry and session shutdown all come through here.
   *
   * The wake that would report the exit is suppressed for a stop, since the
   * caller already told the agent. The log still records who ended it, for a
   * reader that arrives after the session is gone. The group is signalled even
   * when the leader has already exited, so a command's own background children
   * do not outlive a timeout or a stop.
   *
   * @param job - Job to kill.
   * @param marker - How the log should say it ended.
   */
  private kill(job: Job, marker: string): void {
    const { pid } = job.proc;
    if (pid === undefined) {
      return;
    }
    if (job.proc.exitCode === null && job.proc.signalCode === null) {
      signalGroup(pid, "SIGTERM");
      const escalate = setTimeout(
        () => signalGroup(pid, "SIGKILL"),
        KILL_GRACE_MS,
      );
      escalate.unref();
      // A group that ended before the grace period must not be signalled again
      // under a pid the system may have since reused.
      void job.done.then(() => clearTimeout(escalate));
    }
    void job.done.then(() => appendLogMarker(job.logPath, marker));
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
    if (!timer.condition && !timer.start && timer.maxTicks === 0) {
      throw new Error(
        `Timer "${timer.id}" has no condition, no job, and maxTicks 0, so it could never wake you.`,
      );
    }

    if (this.canTick(timer) && timer.timeoutSec < timer.intervalSec) {
      throw new Error(
        `Timer "${timer.id}" cannot tick: timeoutSec ${timer.timeoutSec} is shorter than intervalSec ${timer.intervalSec}.`,
      );
    }
  }

  /**
   * Cancel one timer, stopping its loop and killing its job.
   *
   * The timer is retired as killed, so `/timers` keeps showing it as an ended
   * row instead of dropping it from the list.
   *
   * @param id - Id of the timer to cancel.
   * @returns The cancelled timer, or `undefined` when nothing had that id.
   */
  stop(id: string): Timer | undefined {
    const timer = this.timers.get(id);
    if (!timer) {
      return undefined;
    }

    timer.stopped = true;
    timer.controller.abort();
    if (timer.job) {
      this.kill(timer.job, "killed by timer_stop");
      this.jobs.delete(id);
    }
    this.retire(
      toTimerSpec(timer),
      "killed by timer_stop",
      "killed",
      elapsed(timer.startedAt),
      timer,
    );
    return timer;
  }

  /**
   * Forget a timer that ended, and how and when it ended.
   *
   * Removal from the active map happens here rather than only in the loop's
   * cleanup, so a `timer_stop` that races the farewell wake already sees a
   * stopped timer instead of a live one. The specification is kept with the
   * retirement, so `/timers` can still open the detail of a timer that ended.
   *
   * @param spec - Specification of the timer that just finished.
   * @param reason - Why it finished, e.g. `tick budget spent`.
   * @param state - How it finished, for its marker in `/timers`.
   * @param age - Elapsed time at the end, e.g. `41s`.
   * @param owner - Timer this call expects to retire, when a loop finishes it.
   */
  private retire(
    spec: TimerSpec,
    reason: string,
    state: RunState,
    age: string,
    owner?: Timer,
  ): void {
    // A replaced timer must not retire its replacement: `restore()` re-arms the
    // same ids while an old loop can still be unwinding.
    if (owner && this.timers.get(spec.id) !== owner) {
      return;
    }
    this.timers.delete(spec.id);
    // A re-inserted id moves to the end, so the eviction below drops the timer
    // that ended longest ago rather than the one armed longest ago.
    this.retired.delete(spec.id);
    this.retired.set(spec.id, { reason, state, age, spec });
    // Oldest first: this drops the timer the agent is least likely to still ask
    // about.
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
    return `Timer "${id}" stopped (${this.retired.get(id)?.reason}).`;
  }

  /**
   * Cancel every active timer without signalling the jobs they watch.
   *
   * `restore()` uses this: a branch switch abandons the timers of the old
   * timeline, but the commands they started are not the branch's to kill.
   */
  stopAll(): void {
    for (const timer of this.timers.values()) {
      timer.stopped = true;
      timer.controller.abort();
    }
    this.timers.clear();
    this.retired.clear();
  }

  /**
   * Stop watching and kill every job, for session teardown.
   *
   * Awaited so `SIGTERM` reaches each job before the process exits; the grace
   * escalation still sends `SIGKILL` to anything that ignores it.
   */
  async killJobs(): Promise<void> {
    const jobs = [...this.jobs.values()];
    this.stopAll();
    for (const job of jobs) {
      this.kill(job, "killed at session shutdown");
    }
    // Bounded: a job stuck in uninterruptible sleep must not hold pi open.
    await Promise.race([
      Promise.all(jobs.map((job) => job.done)),
      sleep(KILL_GRACE_MS + 1_000),
    ]);
    this.jobs.clear();
  }

  /** Forget which timers still have a queued notification. */
  clearPending(): void {
    for (const timer of this.timers.values()) {
      timer.noticePending = false;
    }
  }

  /**
   * Collect the active timers as table rows.
   *
   * @returns One row per active timer, oldest first.
   */
  private activeRows(): TimerRow[] {
    return [...this.timers.values()]
      .map((timer) => this.row(timer))
      .sort(byStartedAt);
  }

  /**
   * Collect every timer as table rows for `/timers`.
   *
   * @returns The active rows, then the ended ones, each group oldest first --
   *   the order `/timers` opens with.
   */
  rows(): TimerRow[] {
    const retired = [...this.retired.entries()]
      .map(([id, entry]) => ({
        id,
        state: entry.state,
        age: entry.age,
        ticks: "-",
        target: entry.reason,
        spec: entry.spec,
        reason: entry.reason,
      }))
      .sort(byStartedAt);
    return [...this.activeRows(), ...retired];
  }

  /**
   * Describe every active timer, one line each.
   *
   * Ended timers stay out of this list: the wake that announced the end already
   * told the agent, and `timer_status <id>` still reports one by name.
   *
   * @returns Lines oldest first, or a message when nothing is active.
   */
  list(): string {
    const rows = this.activeRows();
    return rows.length === 0
      ? "No active timers."
      : rows.map(formatTimerRow).join("\n");
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
      return formatTimerRow(this.row(timer));
    }
    return this.retired.has(id) ? this.retirementText(id) : this.unknownId(id);
  }

  /**
   * Look up the timer a `timer_stop` call should cancel.
   *
   * Stopping a timer that already ended is not an error: the agent usually
   * stops it right after the wake that announced the end, and a failure there
   * teaches it nothing. Such a call returns `undefined` so the tool can report
   * that the timer stopped.
   *
   * @param id - Id from the tool input.
   * @returns The active timer, or `undefined` when it already ended.
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
   * Describe one timer as fields for a table row.
   *
   * @param timer - Timer to describe.
   * @returns Id, state, age, tick budget, what it waits for, and the
   *   specification its detail view shows.
   */
  private row(timer: Timer): TimerRow {
    const ticks =
      timer.maxTicks === undefined
        ? `${timer.ticksSent}/unlimited`
        : `${timer.ticksSent}/${timer.maxTicks}`;
    const target = timer.job
      ? `job pid ${timer.job.proc.pid ?? "?"}, log ${timer.job.logPath}`
      : timer.condition
        ? `cond: ${timer.condition}`
        : "timer, no condition";
    return {
      id: timer.id,
      state: "running",
      age: elapsed(timer.startedAt),
      ticks: `ticks ${ticks}`,
      target,
      spec: toTimerSpec(timer),
      pid: timer.job?.proc.pid,
    };
  }

  /**
   * Replace the current timers with those recorded on a session branch.
   *
   * In-flight loops are cancelled first, so a branch switch cannot leave
   * orphaned pollers that keep notifying about an abandoned timeline. A job
   * entry replayed from the transcript is never spawned or signalled again: it
   * either matches a job this process still runs, or it belonged to an earlier
   * pi process and only its log is left.
   *
   * @param entries - Active session branch entries.
   */
  restore(entries: readonly SessionEntry[]): void {
    this.stopAll();

    for (const spec of collectActiveTimers(entries).values()) {
      const job = spec.start ? this.jobs.get(spec.id) : undefined;
      if (spec.start && !job) {
        const log = spec.logPath ? `; log ${spec.logPath}` : "";
        // Its end was never observed, so it can only be reported as failed.
        this.retire(spec, `orphaned${log}`, "failed", elapsed(spec.startedAt));
        continue;
      }
      this.arm({
        ...spec,
        // A live job for this id is what this process actually runs, so it owns
        // the start time, the log and the deadline the wake reports.
        startedAt: job?.startedAt ?? spec.startedAt,
        logPath: job?.logPath ?? spec.logPath,
        ticksSent: 0,
        noticePending: false,
        stopped: false,
        settled: false,
        controller: new AbortController(),
        job,
      });
    }
  }

  /**
   * Register a timer and start its loop without blocking the caller.
   *
   * @param timer - Timer to arm.
   */
  private arm(timer: Timer): void {
    this.timers.set(timer.id, timer);
    this.retired.delete(timer.id);
    const loop = timer.job ? this.watch(timer) : this.poll(timer);
    void loop
      .catch((error) => {
        // Same ownership reason as the `finally` below: a loop replaced by
        // `restore()` must not retire the timer that replaced it.
        if (!timer.stopped && this.timers.get(timer.id) === timer) {
          this.retire(
            toTimerSpec(timer),
            "failed",
            "failed",
            elapsed(timer.startedAt),
            timer,
          );
          this.notify(
            timer,
            "failed",
            `error: ${String(error)}; timer stopped`,
          );
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
      await this.finish(
        timer,
        "done",
        this.conditionLine(timer),
        "condition met",
      );
      return;
    }

    while (!timer.stopped) {
      const waitMs = Math.min(timer.intervalSec * 1000, deadline - Date.now());
      if (waitMs > 0) {
        await sleep(Math.min(waitMs, MAX_TIMEOUT_MS), undefined, {
          signal: timer.controller.signal,
        });
      }
      if (timer.stopped) {
        return;
      }

      if (Date.now() >= deadline) {
        await this.finish(
          timer,
          "timeout",
          `timeout after ${timer.timeoutSec}s`,
          "timed out",
        );
        return;
      }

      if (
        timer.condition &&
        (await this.matches(timer, timer.condition, deadline))
      ) {
        await this.finish(
          timer,
          "done",
          this.conditionLine(timer),
          "condition met",
        );
        return;
      }

      // The callback is the timer body: it runs on every tick even when the
      // wake is throttled, so periodic work is never silently skipped.
      const body = await this.capture(timer);
      // `timer_stop` or a branch restore may have ended the timer while the
      // callback ran; a late tick would wake the agent about a dead timer.
      if (timer.stopped) {
        return;
      }
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
        this.retire(
          toTimerSpec(timer),
          "tick budget spent",
          "done",
          elapsed(timer.startedAt),
          timer,
        );
        return;
      }
    }
  }

  /**
   * Announce a condition that held, naming the predicate that did it.
   *
   * @param timer - Timer whose condition matched.
   * @returns One line for the final wake.
   */
  private conditionLine(timer: Timer): string {
    return `condition met after ${elapsed(timer.startedAt)}: ${timer.condition}`;
  }

  /**
   * Watch a background job until it exits, is killed, or its deadline passes.
   *
   * The exit is an event, so no poll interval decides how soon the wake
   * arrives; `intervalSec` only paces optional progress ticks, and a job timer
   * with no tick budget waits on the exit alone.
   *
   * @param timer - Timer whose `job` owns the process.
   */
  private async watch(timer: Timer): Promise<void> {
    const job = timer.job as Job;
    const deadline = timer.startedAt + timer.timeoutSec * 1000;
    // Captured once: a job that exits as the deadline passes still has an exit
    // code to report, which is better news than "killed".
    let outcome: JobOutcome | undefined;
    void job.done.then((result) => {
      outcome = result;
    });

    while (!timer.stopped) {
      const waitMs = this.canTick(timer)
        ? Math.max(0, Math.min(timer.intervalSec * 1000, deadline - Date.now()))
        : Math.max(0, deadline - Date.now());
      const result = await this.raceJob(timer, job, waitMs);
      if (result === "stopped" || timer.stopped) {
        return;
      }
      if (result !== "wait") {
        await this.finishJob(timer, job, result);
        return;
      }
      if (outcome) {
        await this.finishJob(timer, job, outcome);
        return;
      }
      if (Date.now() >= deadline) {
        await this.expireJob(timer, job);
        return;
      }
      await this.tickJob(timer);
    }
  }

  /**
   * Wait for a job to exit, for the timer to be cancelled, or for `waitMs`.
   *
   * A cancellable timer rather than `sleep()`: a job with no tick budget waits
   * up to its whole deadline, and a pending sleep handle would keep the process
   * alive long after the job ended.
   *
   * @param timer - Timer watching the job.
   * @param job - Job to wait on.
   * @param waitMs - Milliseconds until the next tick, or until the deadline.
   * @returns The job outcome, `wait` when the interval passed, or `stopped`.
   */
  private raceJob(
    timer: Timer,
    job: Job,
    waitMs: number,
  ): Promise<JobOutcome | "wait" | "stopped"> {
    const { signal } = timer.controller;
    return new Promise((resolve) => {
      let handle: NodeJS.Timeout | undefined;
      const finish = (result: JobOutcome | "wait" | "stopped") => {
        clearTimeout(handle);
        signal.removeEventListener("abort", onAbort);
        resolve(result);
      };
      const onAbort = () => finish("stopped");
      // `setTimeout` overflows above 2^31-1 ms and then fires immediately, which
      // would spin this loop; the deadline check ends the timer on the next pass.
      handle = setTimeout(
        () => finish("wait"),
        Math.min(waitMs, MAX_TIMEOUT_MS),
      );
      signal.addEventListener("abort", onAbort, { once: true });
      void job.done.then((outcome) => finish(outcome));
    });
  }

  /**
   * Send one progress tick while a job runs.
   *
   * Matches a periodic timer: the callback runs even when its wake is
   * throttled, and a dropped wake costs no tick budget.
   *
   * @param timer - Job timer to tick.
   */
  private async tickJob(timer: Timer): Promise<void> {
    const body = await this.capture(timer);
    if (timer.stopped || timer.noticePending || !this.canTick(timer)) {
      return;
    }
    this.tick(timer, body, false);
  }

  /**
   * End a job timer whose deadline passed, killing the job it watches.
   *
   * A job nobody watches must not keep running until session shutdown, so the
   * deadline takes the process with it.
   *
   * @param timer - Job timer whose deadline passed.
   * @param job - Job to kill.
   */
  private async expireJob(timer: Timer, job: Job): Promise<void> {
    // Out of `jobs` first: a `restore()` during the grace window must not
    // re-attach a job this loop is already killing.
    this.jobs.delete(job.id);
    this.kill(job, "killed by the timer");
    await job.done;
    if (timer.stopped) {
      return;
    }
    await this.finish(
      timer,
      "timeout",
      `timeout after ${timer.timeoutSec}s; job killed`,
      "timed out",
    );
  }

  /**
   * Report a job that ended by itself, with its exit status and log tail.
   *
   * @param timer - Timer that watched the job.
   * @param job - Job that ended.
   * @param outcome - Exit code, signal, or spawn failure.
   */
  private async finishJob(
    timer: Timer,
    job: Job,
    outcome: JobOutcome,
  ): Promise<void> {
    this.jobs.delete(job.id);
    const end = describeJobEnd(outcome, elapsed(timer.startedAt));
    appendLogMarker(job.logPath, end.marker);
    await this.finish(timer, jobEndState(outcome), end.line, end.reason);
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
      `tick ${count}, ${elapsed(timer.startedAt)} elapsed${ending}`,
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
   * The wake carries the end of the job log when the timer ran a command, then
   * the `onTick` output if there is any, so a job wake answers the question the
   * agent would otherwise go ask with another tool call.
   *
   * The timer leaves the active map before the callback runs, so a `timer_stop`
   * that lands during a slow `onTick` sees it gone and reports the retirement
   * instead of killing a job that already ended.
   *
   * @param timer - Timer that finished.
   * @param state - Why it finished.
   * @param line - News for the wake, without the trailing `; timer stopped`.
   * @param reason - Short reason a later `timer_stop` reports.
   */
  private async finish(
    timer: Timer,
    state: "done" | "timeout" | "failed" | "killed",
    line: string,
    reason: string,
  ): Promise<void> {
    if (timer.settled) {
      return;
    }
    timer.settled = true;
    this.retire(
      toTimerSpec(timer),
      reason,
      state,
      elapsed(timer.startedAt),
      timer,
    );
    const tail = timer.job ? readLogTail(timer.job.logPath) : "";
    const body = [tail, await this.capture(timer)].filter(Boolean).join("\n");
    if (timer.stopped) {
      return;
    }
    this.notify(timer, state, `${line}; timer stopped`, body);
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
    // A blank line keeps the captured output its own block instead of letting a
    // log line continue the summary paragraph.
    const content = body
      ? `[timer ${timer.id}] ${line}\n\n${body}`
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
  if (spec.start) {
    const ticks =
      spec.maxTicks === 0
        ? "no tick wakes"
        : `tick wakes every ${spec.intervalSec}s`;
    return `Started job "${spec.id}": runs \`${spec.start}\` in the background, ${ticks}, log ${spec.logPath}; wakes you when it exits or after ${spec.timeoutSec}s. It is killed when this session ends.`;
  }

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
      "Run a command in the background, wait for a condition, or tick on a schedule; every mode returns immediately. " +
      'What ends the timer is the mode. With `start`: the process exits -- `timer_start { "id": "build", "start": "make" }` ' +
      "runs it in the background, logs to ~/.pi/agent/jobs/<id>-<startedAt>.log, and wakes you once with the exit code and the log tail. " +
      "With `condition`: the predicate exits 0, checked now and at each intervalSec. " +
      "With neither: periodic mode, onTick does the work and you get one wake per tick. " +
      "start and condition are mutually exclusive: pass exactly one, or neither. " +
      "onTick runs on every tick, and its output accompanies wakes. " +
      "timer_stop, a timeoutSec expiry, or the end of the session (including /reload, /resume and /new) kills a running job.",
    promptSnippet:
      "Start a background command and wake when it exits, wait for a condition, or tick periodically.",
    promptGuidelines: [
      "For a command that may take a while, use `timer_start` with `start`, never bash `&`, pid or exit files, polling, or `sleep N` waits. Keep working or end your turn: an idle agent is woken in a new turn.",
      "A tick or condition wake from a timer says only that something happened; a job wake already carries the exit code and log tail. After a wake, do what it asks, then `timer_stop` a timer you no longer need.",
    ],
    parameters: TimerStartParams,

    async execute(
      _toolCallId: string,
      params: TimerStartInput,
      _signal: AbortSignal | undefined,
      _onUpdate: AgentToolUpdateCallback<TimerDetails> | undefined,
      ctx: ExtensionToolContext,
    ) {
      const spec = registry.start(params, ctx?.cwd ?? process.cwd());
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
    description:
      "Cancel a running timer, killing the job it started if it has one, so it stops ticking and waking you.",
    parameters: TimerStopParams,

    async execute(_toolCallId: string, params: TimerStopInput) {
      const id = requireId(params.id);
      const target = registry.requireStopTarget(id);
      if (!target) {
        return timerResult(registry.retirementText(id), { action: "stop", id });
      }
      const stopped = registry.stop(id);
      const killed = stopped?.job
        ? `; killed its job, log ${stopped.job.logPath}`
        : "";
      return timerResult(`Stopped "${id}"${killed}.`, { action: "stop", id });
    },
  };
}

/** What a timer's detail body shows. */
interface LogTail {
  /** One dim line per log line, oldest first, or the empty-state line. */
  lines: string[];
  /** Whether these are log lines, rather than a placeholder for no log. */
  content: boolean;
}

/**
 * Overlay listing the session's timers, running ones first.
 *
 * Built on the shared overlay page, like `/subagents`: a bordered box with a
 * title, a summary, one line per timer and an Escape hint. Rows are read on
 * every render, so elapsed times stay current and a timer that just ended turns
 * into its finished row without reopening the view; the order of the rows is
 * the one the view opened with, so a running timer that ends keeps its place
 * instead of moving to the finished group mid-read. Enter opens one timer's
 * detail, the tail of its job log included, and Escape walks back out. A
 * running timer gets the same braille spinner as pi's working indicator; the
 * animation runs only while one is running.
 */
class TimersOverlay implements Component {
  private readonly page: OverlayPage;
  private readonly nav: DrillDown;
  private readonly theme: Theme;
  /** User keybindings, so the list moves with the keys every pi list uses. */
  private readonly keybindings: KeybindingsManager;
  private readonly readRows: () => TimerRow[];
  /**
   * Ids in the order the view opened with.
   *
   * The registry orders rows by state and then by creation time, which is the
   * order to start from but not one to re-apply: a timer that ends during the
   * session would jump out of the row the reader is looking at. Pinning the ids
   * once keeps every row in place, while the fields of each row stay live.
   */
  private readonly order: readonly string[];
  private readonly close: () => void;
  private readonly spinner: Spinner;

  constructor(
    tui: TUI,
    theme: Theme,
    keybindings: KeybindingsManager,
    readRows: () => TimerRow[],
    close: () => void,
  ) {
    this.theme = theme;
    this.keybindings = keybindings;
    this.readRows = readRows;
    this.close = close;
    this.order = readRows().map((row) => row.id);
    this.page = new OverlayPage(tui, theme, "Timers");
    this.nav = new DrillDown(() => tui.requestRender());
    this.spinner = new Spinner(() => tui.requestRender());
    this.syncRefresh();
  }

  /**
   * The rows to show, in the order the view opened with.
   *
   * A timer armed while the view is open has no place yet, so it goes last,
   * where the registry order puts it.
   *
   * @returns One row per timer, its fields read fresh.
   */
  private currentRows(): TimerRow[] {
    const live = this.readRows();
    const byId = new Map(live.map((row) => [row.id, row]));
    const pinned = this.order
      .map((id) => byId.get(id))
      .filter((row) => row !== undefined);
    const fresh = live.filter((row) => !this.order.includes(row.id));
    return [...pinned, ...fresh];
  }

  render(width: number): string[] {
    const rows = this.currentRows();
    const { selected, detail } = this.nav.sync(rows, (row) => row.id);
    this.page.setSummary(
      detail
        ? detailTitle(
            detail,
            this.spinner.marker(detail.state, this.theme),
            this.theme,
          )
        : summaryOf(rows, this.theme),
    );
    // The specification is pinned, so the log tail below it keeps its rows.
    this.page.setHead(detail ? [detailSpec(detail, this.theme)] : []);
    if (detail) this.detailBody(detail, width);
    else this.listBody(rows, selected, width);
    this.syncRefresh(rows);
    return this.page.render(width);
  }

  invalidate(): void {
    this.syncRefresh();
    this.page.invalidate();
  }

  /** Stop the animation once the overlay is closed. */
  dispose(): void {
    this.spinner.stop();
  }

  handleInput(data: string): void {
    const ids = this.currentRows().map((row) => row.id);
    const closing = this.nav.handleInput(
      data,
      this.keybindings,
      ids,
      this.page.rowCapacity,
    );
    if (!closing) return;
    this.close();
  }

  /**
   * Render the list view, scrolled so the selected timer stays visible.
   *
   * @param rows - Rows the overlay shows.
   * @param selected - Index of the selected row within all rows.
   * @param width - Overlay width, including the text padding.
   */
  private listBody(
    rows: readonly TimerRow[],
    selected: number,
    width: number,
  ): void {
    // The hint names Enter only while there is a row to open.
    const hint =
      rows.length === 0
        ? "Press Escape to close"
        : "Enter for details, Escape to close";
    const capacity = this.page.measure(width, hint);
    const start = windowStart(selected, rows.length, capacity);
    this.page.setWindow(
      this.renderRows(rows, width, selected),
      start,
      capacity,
      hint,
      width,
    );
  }

  /**
   * Render one timer's detail body: the tail of its job log.
   *
   * The log is read on every render, so a running job's progress stays live
   * while the view is open. That read is bounded, so a log that grew for hours
   * costs no more than a short one.
   *
   * @param row - Timer whose detail is open.
   * @param width - Overlay width, including the text padding.
   */
  private detailBody(row: TimerRow, width: number): void {
    const tail = this.logTail(row);
    const hint = "Escape to go back";
    let capacity = this.page.measure(width, `${hint}, up/down scroll`);
    // The specification may wrap, so it takes rows the log needs. A log with no
    // row of its own is what the reader came for, so the head goes then: the
    // list row already names the pid and the log path.
    if (capacity === 0 && tail.content) {
      this.page.setHead([]);
      capacity = this.page.measure(width, `${hint}, up/down scroll`);
    }
    const start = this.nav.detailWindow(tail.lines.length, capacity);
    const inner = Math.max(0, width - PAGE_PADDING_X * 2);
    this.page.setWindow(
      tail.lines.map((line) => truncateToWidth(line, inner, "...", true)),
      start,
      capacity,
      hint,
      width,
    );
  }

  /**
   * Tail of the job log a timer writes, or the empty state when it has none.
   *
   * @param row - Timer whose detail is open.
   * @returns The dim lines to show, and whether they are log output rather than
   *   a placeholder for an empty or missing log.
   */
  private logTail(row: TimerRow): LogTail {
    const { theme } = this;
    const path = row.spec.logPath;
    if (!path) return { lines: [], content: false };
    const text = readLogTail(path, DETAIL_TAIL_LINES, LOG_TAIL_BYTES);
    if (!text) {
      const empty = existsSync(path)
        ? "(the log is empty)"
        : "(no log was written)";
      return { lines: [theme.fg("dim", empty)], content: false };
    }
    return {
      lines: text.split("\n").map((line) => theme.fg("dim", line)),
      content: true,
    };
  }

  /**
   * Render every timer on one line each, with aligned, highlighted columns.
   *
   * The id comes first and the marker after it, so the markers of all rows form
   * one column, matching `/subagents`.
   *
   * @param rows - Every row of the list.
   * @param width - Overlay width, including the text padding.
   * @param selected - Index of the selected row within all rows.
   * @returns One width-truncated line per timer.
   */
  private renderRows(
    rows: readonly TimerRow[],
    width: number,
    selected: number,
  ): string[] {
    const { theme } = this;
    const widths = timerWidths(rows);
    const inner = Math.max(0, width - PAGE_PADDING_X * 2);
    return rows.map((row, index) => {
      const current = index === selected;
      const id = padRight(row.id, widths.id);
      // Every row reserves the cursor column, so selection never shifts it.
      const cursor = current ? theme.fg("accent", SELECTED_CURSOR) : " ";
      return truncateToWidth(
        [
          cursor,
          current ? theme.fg("accent", theme.bold(id)) : theme.bold(id),
          this.spinner.marker(row.state, theme),
          theme.fg("muted", padRight(row.state, widths.state)),
          theme.fg("muted", padRight(row.age, widths.age)),
          theme.fg("dim", padRight(row.ticks, widths.ticks)),
          theme.fg("dim", row.target),
        ].join(" "),
        inner,
        "...",
        true,
      );
    });
  }

  /**
   * Animate the spinner while some timer is still running.
   *
   * @param rows - Rows to inspect; read live when omitted.
   */
  private syncRefresh(rows: readonly TimerRow[] = this.currentRows()): void {
    this.spinner.sync(rows.some((row) => row.state === "running"));
  }
}

/**
 * Build the `/timers` command.
 *
 * @param registry - Timer registry shared with the tools.
 * @returns Command definition registered with Pi.
 */
function timersCommand(registry: TimerRegistry) {
  return {
    description: "Show this session's timers in a live overlay",
    handler: async (_args: string, ctx: ExtensionCommandContext) => {
      if (ctx.mode !== "tui") {
        ctx.ui.notify(registry.list(), "info");
        return;
      }

      let overlay: TimersOverlay | undefined;
      try {
        await ctx.ui.custom<void>((tui, theme, keybindings, done) => {
          overlay = new TimersOverlay(
            tui,
            theme,
            keybindings,
            () => registry.rows(),
            () => done(),
          );
          return overlay;
        });
      } finally {
        overlay?.dispose();
      }
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
      "Report every active timer: id, age, ticks spent, and what it waits for -- a condition, a running job with its pid and log, or neither. Name an id to report just that timer.",
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
 * @param pi - Extension API used to register the tools, the `/timers`
 *   command, and session cleanup.
 */
export default function timer(pi: ExtensionAPI): void {
  const registry = new TimerRegistry(pi);

  pi.registerTool(timerStartTool(registry));
  pi.registerTool(timerStopTool(registry));
  pi.registerTool(timerStatusTool(registry));
  pi.registerCommand("timers", timersCommand(registry));

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
  pi.on("session_shutdown", async () => registry.killJobs());
}
