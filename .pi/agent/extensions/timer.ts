/**
 * All the things related to async and periodic jobs.
 *
 * Background timer tools: `timer_start`, `timer_stop`, `timer_status`.
 *
 * A timer combines three optional parts:
 *
 * - A background command that logs its output (`start`)
 * - A callback run on every tick (`onTick`)
 * - A shell predicate that ends the timer when it holds (`condition`)
 *
 * Any combination is allowed. A timer ends when its job exits, its condition
 * exits 0, a periodic timer spends its tick budget, or its deadline passes.
 * Every ending wakes the agent with a short notification. While a job runs,
 * `onTick` and `condition` read its output on stdin. Timers are named by the
 * agent, so every wake and the status list are self-describing.
 *
 * A timer outlives the pi process that armed it. Its job runs detached with
 * its output going to a log, and the registry checkpoints every timer to a
 * per-session state file under the agent dir, so quitting pi, reloading
 * extensions, rebooting, and resuming the session bring the timers back.
 * `timeoutSec` counts a different clock depending on what it bounds: a job
 * keeps running, so its deadline is real time and the job's own shell enforces
 * it even while pi is closed; a timer without a job only acts while pi runs,
 * so its budget is pi-live time and the clock stops while pi is not running.
 * A resumed job whose process is still alive is re-attached by its verified
 * pid; one that ended meanwhile is reported once, with whatever its log
 * recorded. The user-facing `/timers` command shows the session's timers as an
 * aligned table:
 * the running ones first, then the ones that ended, each with the same state
 * marker the `/subagents` view uses. The order is fixed when the view opens and
 * does not follow state changes after that, so no row moves under the reader.
 * Enter opens one timer's detail: what it runs or waits for, its deadline or
 * budget, and the tail of the job log it writes.
 */

import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import {
  appendFileSync,
  closeSync,
  existsSync,
  fstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  readSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import {
  type AgentToolUpdateCallback,
  DEFAULT_MAX_BYTES,
  DEFAULT_MAX_LINES,
  type ExtensionAPI,
  type ExtensionCommandContext,
  type ExtensionContext,
  type ExtensionToolContext,
  formatSize,
  getAgentDir,
  type KeybindingsManager,
  type SessionEntry,
  type SessionStartEvent,
  type Theme,
  type ToolDefinition,
  truncateTail,
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
  listRow,
  OverlayPage,
  padRight,
  SELECTED_CURSOR,
} from "./utils/overlay.ts";
import { PAGE_PADDING_X, windowStart } from "./utils/page.ts";
import { type RunState, Spinner } from "./utils/spinner.ts";

export {
  DEFAULT_TIMEOUT_SEC,
  JOB_TAIL_LINES,
  RETIRED_HISTORY,
  SELECTED_CURSOR,
};

// Timer duration, polling, and notification defaults, in seconds.
const DEFAULT_TIMEOUT_SEC = 3_600;
const MIN_TIMEOUT_SEC = 1;

const DEFAULT_INTERVAL_SEC = 60;
const MIN_INTERVAL_SEC = 1;

// How long a job gets between SIGTERM and SIGKILL, in milliseconds.
const KILL_GRACE_MS = 5_000;

// Largest delay `setTimeout` honors; anything above it fires immediately.
const MAX_TIMEOUT_MS = 2 ** 31 - 1;

// Job logs live under the agent dir, one file per run.
const JOB_LOG_DIR = "jobs";

// One timer state file per session, under the agent dir, so a resumed session
// finds the timers it left running.
const TIMER_STATE_DIR = "timers";
const STATE_VERSION = 1;

// How often a running timer checkpoints its pi-live time, which bounds what a
// crash or power loss can lose; a graceful shutdown checkpoints exactly.
const CHECKPOINT_MS = 30_000;

// How often a re-attached job is checked for having exited while pi was away.
const ADOPT_POLL_MS = 2_000;

// How late the registry's cleanup may fire after a job's own shell deadline:
// the wrapper signals TERM, waits KILL_GRACE_MS, then signals KILL, so the
// registry only steps in if that shell is gone or broken.
const JOB_BACKSTOP_SLACK_MS = KILL_GRACE_MS + 2_000;

// Marks a job shell in its command line, so a resumed process can tell the job
// from an unrelated process that inherited its pid after a reboot.
const JOB_TAG_PREFIX = "# pi-timer-job ";

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

// Snapshot deadline for the optional `onTick` callback.
const ON_TICK_TIMEOUT_MS = 10_000;

/**
 * Accepted timer ids.
 *
 * A slug rather than free text, because the id names the job log file.
 */
const ID_PATTERN_SOURCE = "^[A-Za-z0-9][A-Za-z0-9._-]{2,39}$";

/** Runtime form of `ID_PATTERN_SOURCE`. */
const ID_PATTERN = new RegExp(ID_PATTERN_SOURCE);

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
    pattern: ID_PATTERN_SOURCE,
    description:
      "Timer name: short, unique, purpose-bearing, e.g. batch3-done. It appears in every wake and names the job log.",
  }),
  start: Type.Optional(
    Type.String({
      description:
        "Shell command to run detached in the background and log. It keeps running after pi closes, and is re-attached when the session resumes. The timer ends when it exits, and the wake carries the exit code and log tail. Combine with `condition` and/or `onTick` to monitor it.",
    }),
  ),
  condition: Type.Optional(
    Type.String({
      description:
        "Shell predicate checked immediately, then at each tick; exit 0 ends the timer with 'condition met' and kills a running job. Its stdin is the job's log when `start` is set.",
    }),
  ),
  onTick: Type.Optional(
    Type.String({
      description:
        "Shell command run on every tick, including the one that ends a periodic timer; its output rides along with the wake, capped like a tool result, with the full text saved to a file when large. Never block or sleep. With `start` it also runs once at exit, and its stdin is the job's log.",
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
        "Maximum tick wakes. 0 disables tick wakes, the default with `start`; above 0 runs `onTick` every intervalSec while a job runs. Periodic mode needs at least 1. A condition is still checked every intervalSec when 0. Exit, condition and timeout wakes do not count.",
      minimum: 0,
    }),
  ),
  timeoutSec: Type.Optional(
    Type.Number({
      description:
        "For a `start` job: seconds of real time before the job is killed, counting while pi is closed; the job is detached, so a running-time budget could never bound it, and its own shell enforces this deadline. Without a job: a budget of running time, because nothing runs while pi is closed.",
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
type TimerState = "tick" | "done" | "timeout" | "failed" | "killed";

/** Persisted specification of one timer. */
interface TimerSpec {
  /** Agent-chosen name, unique among active timers. */
  id: string;
  /** Shell command run in the background; the timer ends when it exits. */
  start?: string;
  /** Absolute path of the job log; set with `start`. */
  logPath?: string;
  /** Shell predicate; exit code 0 ends the timer, and kills a running job. */
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
  /**
   * The job ended while no pi process watched it, so its exit status is gone.
   *
   * Only a re-attached job can end this way; its log still says what it did.
   */
  lost?: boolean;
  /**
   * The job's own shell killed it at its deadline.
   *
   * The wrapper writes a marker to the log before it signals, so this survives
   * a pi restart; a live exit is classified from the same marker.
   */
  timedOut?: boolean;
}

/** A background command owned by one timer. */
interface Job {
  id: string;
  /** Absolute path of the log the job writes to. */
  logPath: string;
  /** Unix timestamp in milliseconds when the job was spawned. */
  startedAt: number;
  /**
   * Token in the job shell's command line.
   *
   * A resumed process verifies it before trusting a pid read from disk, so a
   * reboot that reused the pid cannot make a timer signal a stranger.
   */
  tag: string;
  /** Process-group leader, or `undefined` when the spawn failed. */
  pid?: number;
  /** Child handle, only while this process spawned the job. */
  proc?: ChildProcess;
  /** The outcome, once the job ended. */
  exit?: JobOutcome;
  /** Resolves once the process exited, or a re-attached one vanished. */
  done: Promise<JobOutcome>;
}

/** One active timer. */
interface Timer extends TimerSpec {
  /**
   * Pi-live milliseconds the timer had run at `liveSince`.
   *
   * Time while pi was not running does not count against `timeoutSec`, so
   * elapsed time is this checkpoint plus the current process's monotonic time.
   */
  activeMs: number;
  /** `performance.now()` at the moment `activeMs` was last checkpointed. */
  liveSince: number;
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

/** A job a resumed process can re-attach to, as written to its state file. */
interface PersistedJob {
  /** Process-group leader, absent when the spawn never produced one. */
  pid?: number;
  /** Absolute path of the job log. */
  logPath: string;
  /** Unix timestamp in milliseconds when the job was spawned. */
  startedAt: number;
  /** Token the job shell was started with, to verify the pid. */
  tag: string;
}

/** One timer as written to a session's state file. */
interface PersistedTimer extends TimerSpec {
  /** Pi-live milliseconds the timer had run at the checkpoint. */
  activeMs: number;
  /** Tick wakes delivered before the checkpoint. */
  ticksSent: number;
  /** Background job the timer watched, when it has one. */
  job?: PersistedJob;
}

/** Contents of one session's timer state file. */
interface TimerStateFile {
  version: number;
  /** Session the timers belong to. */
  sessionId: string;
  /** Wall-clock time of the checkpoint, for diagnosis. */
  updatedAt: number;
  timers: PersistedTimer[];
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
 * Pi-live milliseconds a timer has been running.
 *
 * `activeMs` holds what earlier pi processes observed; the rest is this
 * process's monotonic clock. Wall-clock time while pi was not running is in
 * neither term, so a restart neither spends a timer's budget nor shortens it.
 *
 * @param timer - Timer to measure.
 * @returns Elapsed pi-live milliseconds.
 */
function liveMs(timer: Timer): number {
  return timer.activeMs + (performance.now() - timer.liveSince);
}

/**
 * How long a timer has been running, in the clock its limit uses.
 *
 * A job keeps running while pi is closed, so its age is real time since the
 * spawn; a schedule only acts while pi does, so its age is pi-live time.
 *
 * @param timer - Timer to measure.
 * @returns Age in milliseconds.
 */
function ageMs(timer: Timer): number {
  return timer.job ? Date.now() - timer.job.startedAt : liveMs(timer);
}

/**
 * Format a duration in whole seconds.
 *
 * @param ms - Duration in milliseconds.
 * @returns Text such as `40s`.
 */
function durationText(ms: number): string {
  return `${Math.floor(ms / 1000)}s`;
}

/**
 * Quote a value as one literal shell word.
 *
 * Single quotes keep every metacharacter literal; an embedded quote is closed,
 * escaped and reopened.
 *
 * @param value - Raw value, such as a log path.
 * @returns The value wrapped for use in a `bash -c` script.
 */
function shellQuote(value: string): string {
  return `'${value.replace(/'/g, "'\\''")}'`;
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
  // The two kinds of timer measure different clocks, and the label has to say
  // which one, or a resumed timer's numbers look wrong.
  const limit = row.spec.start
    ? `deadline=${row.spec.timeoutSec}s`
    : `budget=${row.spec.timeoutSec}s running`;
  return [
    theme.bold(row.id),
    stateMarker,
    theme.fg("muted", state),
    theme.fg("dim", limit),
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
 * Absolute path of one file under the job log directory.
 *
 * @param name - File name within that directory.
 * @returns The absolute path, with the directory created.
 */
function jobLogPath(name: string): string {
  const path = join(getAgentDir(), JOB_LOG_DIR, name);
  mkdirSync(dirname(path), { recursive: true });
  return path;
}

/**
 * Absolute path of a session's timer state file.
 *
 * @param sessionId - Session whose timers it holds.
 * @returns The path, without creating anything: a session with no active timer
 *   has no file, which is what marks it as having nothing to resume.
 */
function timerStatePath(sessionId: string): string {
  return join(getAgentDir(), TIMER_STATE_DIR, `${sessionId}.json`);
}

/**
 * Whether one record from a state file can be armed as it stands.
 *
 * A record that lost its numbers, or picked up a value that would make a wait
 * loop spin, is dropped: a hand-edited or damaged file must not turn into a
 * busy timer.
 *
 * @param timer - Record read from the state file.
 * @returns `true` when every field a timer loop depends on is usable.
 */
function isPersistedTimer(timer: PersistedTimer): boolean {
  if (typeof timer !== "object" || timer === null) {
    return false;
  }
  return (
    typeof timer.id === "string" &&
    ID_PATTERN.test(timer.id) &&
    Number.isFinite(timer.activeMs) &&
    timer.activeMs >= 0 &&
    Number.isFinite(timer.ticksSent) &&
    timer.ticksSent >= 0 &&
    Number.isFinite(timer.intervalSec) &&
    timer.intervalSec >= MIN_INTERVAL_SEC &&
    Number.isFinite(timer.timeoutSec) &&
    timer.timeoutSec >= MIN_TIMEOUT_SEC
  );
}

/**
 * Read the timer state a session left behind.
 *
 * @param sessionId - Session whose timers to read.
 * @returns The saved state with only usable records, or `undefined` when the
 *   session left nothing to resume.
 */
function readTimerState(sessionId: string): TimerStateFile | undefined {
  const path = timerStatePath(sessionId);
  if (!existsSync(path)) {
    return undefined;
  }
  let state: TimerStateFile;
  try {
    state = JSON.parse(readFileSync(path, "utf8")) as TimerStateFile;
  } catch {
    // A file that cannot be read costs only this session's timers, but leaving
    // it in place would fail every later start of that session too.
    rmSync(path, { force: true });
    return undefined;
  }
  if (state.version !== STATE_VERSION) {
    // A file from another build cannot be attributed to a live job, so it is
    // ignored rather than guessed at.
    return undefined;
  }
  const timers = Array.isArray(state.timers)
    ? state.timers.filter(isPersistedTimer)
    : [];
  return { ...state, timers };
}

/** Wake-ready callback output, plus the file holding the full text. */
interface CallbackOutput {
  /** Preview, or the whole output when it fits. */
  text: string;
  /** File containing the full output, when `text` is only a preview. */
  savedPath?: string;
}

/**
 * Format a callback snapshot for a wake.
 *
 * Output within Pi's tool-output limits is returned unchanged. A larger
 * snapshot keeps the tail as the preview and writes the complete text to a job
 * file, so the agent can read it without the wake carrying the whole thing.
 *
 * @param id - Timer id, which names the file.
 * @param output - Combined stdout and stderr from the callback.
 * @returns Wake-ready text and the full-output file, if one was written.
 */
async function formatCallbackOutput(
  id: string,
  output: string,
): Promise<CallbackOutput> {
  if (!output.trim()) {
    return { text: "" };
  }

  const truncation = truncateTail(output, {
    maxLines: DEFAULT_MAX_LINES,
    maxBytes: DEFAULT_MAX_BYTES,
  });
  if (!truncation.truncated) {
    return { text: output.trim() };
  }

  const path = jobLogPath(`${id}-ontick-${randomUUID()}.log`);
  await writeFile(path, output);

  const startLine = truncation.totalLines - truncation.outputLines + 1;
  const endLine = truncation.totalLines;
  const notice = truncation.lastLinePartial
    ? `[Showing last ${formatSize(truncation.outputBytes)} of line ${endLine}. Full output: ${path}]`
    : truncation.truncatedBy === "lines"
      ? `[Showing lines ${startLine}-${endLine} of ${truncation.totalLines}. Full output: ${path}]`
      : `[Showing lines ${startLine}-${endLine} of ${truncation.totalLines} (${formatSize(truncation.maxBytes)} limit). Full output: ${path}]`;
  return {
    text: [truncation.content.trimEnd(), notice].filter(Boolean).join("\n\n"),
    savedPath: path,
  };
}

/**
 * Classify how a job ended, for its wake and its `/timers` marker.
 *
 * @param outcome - Exit code, signal, spawn failure, or a job that ended while
 *   pi was not watching it.
 * @returns `killed` for a signal from outside the timer, `done` for exit 0,
 *   and `failed` otherwise.
 */
function jobEndState(outcome: JobOutcome): "done" | "failed" | "killed" {
  if (outcome.error || outcome.lost) return "failed";
  if (outcome.signal) return "killed";
  return outcome.code === 0 ? "done" : "failed";
}

/**
 * Name how a job ended, for its wake, its log, and its retirement reason.
 *
 * @param outcome - Exit code, signal, spawn failure, or a job that ended while
 *   pi was not watching it.
 * @param elapsedText - Time since the job started, e.g. `41s`.
 * @returns The wake line and the short reason for `timer_stop`.
 */
function describeJobEnd(
  outcome: JobOutcome,
  elapsedText: string,
): { line: string; reason: string } {
  if (outcome.lost) {
    return {
      line: `the job ended while pi was not running, after ${elapsedText}`,
      reason: "ended while pi was not running",
    };
  }
  if (outcome.error) {
    return {
      line: `failed to start: ${outcome.error}`,
      reason: "failed to start",
    };
  }
  if (outcome.signal) {
    return {
      line: `killed by ${outcome.signal} after ${elapsedText}, not by the timer`,
      reason: `killed by ${outcome.signal}`,
    };
  }
  return {
    line:
      outcome.code === 0
        ? `exited 0 after ${elapsedText}`
        : `failed: exit ${outcome.code} after ${elapsedText}`,
    reason: outcome.code === 0 ? "exited 0" : `failed: exit ${outcome.code}`,
  };
}

/**
 * Append to a job log how something other than its shell ended it.
 *
 * A job that exits by itself records its own `[exit N]` marker, so this covers
 * a job the timer signalled and one a signal from outside ended: neither has a
 * shell left to write the line. The log outlives the wake that reported the
 * end, so the file has to say it too. A job that failed to spawn has no log to
 * write to, and a log that disappeared is not worth an error.
 *
 * @param path - Absolute path of the job log.
 * @param marker - Short status, e.g. `killed by timer_stop`.
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
 * Whether a pid is still alive.
 *
 * `process.kill(pid, 0)` checks without signalling; ESRCH means it is gone.
 *
 * @param pid - Pid to check.
 * @returns `true` while the process exists.
 */
function pidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

/**
 * Whether a pid still runs the job shell carrying this tag.
 *
 * A leader pid can be recycled after a reboot, so the tag in the command line
 * is the identity that matters. `ps` is the portable way to read it, and a pid
 * that no longer exists makes it fail, which is the answer too.
 *
 * @param pid - Recorded process-group leader.
 * @param tag - Token the job shell was started with.
 * @returns `true` while that shell is alive.
 */
function jobAlive(pid: number, tag: string): boolean {
  try {
    const command = execFileSync("ps", ["-o", "command=", "-p", String(pid)], {
      encoding: "utf8",
      // A pid that no longer exists makes ps complain; that is just "gone".
      stdio: ["ignore", "pipe", "ignore"],
    });
    return command.includes(`${JOB_TAG_PREFIX}${tag}`);
  } catch {
    return false;
  }
}

/** What the wrapper's own lines at the end of a job log say. */
interface JobLogStatus {
  /** The deadline marker is a line of its own in the log. */
  marker: boolean;
  /** Last exit code the wrapper recorded, when it could write one. */
  exitCode: number | null;
}

/**
 * Whether a line is exactly the wrapper's deadline marker.
 *
 * The comparison is whole-line because the marker text also appears inside the
 * wrapper's own command line, which a job that dumps `ps` can write to its log.
 *
 * @param line - One log line.
 * @param tag - Token that identifies the job's shell.
 * @returns `true` when the line is that job's deadline marker.
 */
function isDeadlineMarkerLine(line: string, tag: string): boolean {
  const prefix = `[pi-timer ${tag}: timeout after `;
  if (!line.startsWith(prefix) || !line.endsWith("s]")) {
    return false;
  }
  const seconds = line.slice(prefix.length, -"s]".length);
  return seconds !== "" && Number.isFinite(Number(seconds));
}

/**
 * Read the wrapper's own status lines from a job log.
 *
 * A wider window than a wake uses: a TERM handler can flush many lines after
 * the deadline marker, and evicting the marker would misreport the end.
 *
 * @param logPath - Absolute path of the job log.
 * @param tag - Token that identifies the job's shell.
 * @returns The marker, and the last exit code the wrapper wrote.
 */
function readJobStatus(logPath: string, tag: string): JobLogStatus {
  const text = readLogTail(logPath, DETAIL_TAIL_LINES, LOG_TAIL_BYTES);
  let marker = false;
  let exitCode: number | null = null;
  for (const line of text.split("\n")) {
    const exit = /^\[exit (\d+)\]$/.exec(line);
    if (exit) exitCode = Number(exit[1]);
    if (isDeadlineMarkerLine(line, tag)) marker = true;
  }
  return { marker, exitCode };
}

/**
 * Whether a job ended at its own shell's deadline.
 *
 * The wrapper's own exit line is the truth when it wrote one, so a clean exit
 * wins over a marker the watchdog wrote just as the command finished; anything
 * else that died after a marker was written was ended by the deadline.
 *
 * @param job - Job that ended.
 * @param outcome - Exit code, signal, or a recovered status.
 * @returns `true` when the deadline ended the job.
 */
function endedByDeadline(job: Job, outcome: JobOutcome): boolean {
  if (outcome.timedOut) return true;
  if (outcome.error || outcome.lost) return false;
  const status = readJobStatus(job.logPath, job.tag);
  const code = status.exitCode ?? outcome.code;
  const signalled = status.exitCode === null && Boolean(outcome.signal);
  if (code === 0 && !signalled) return false;
  return status.marker;
}

/**
 * Recover how a job ended from its log after pi restarted.
 *
 * The wrapper writes the deadline marker before it signals and `[exit N]` as
 * its last act, so both survive a pi restart even though the child process
 * handle does not. The last exit line wins over an earlier one because a job's
 * own background child can print after the wrapper's line. Without either line
 * the job was signalled directly or the machine rebooted: its status is gone,
 * but the log tail still says what it did.
 *
 * @param logPath - Absolute path of the job log.
 * @param tag - Token that identifies the job's shell.
 * @returns The recovered outcome, or an outcome flagged as lost.
 */
function recoverOutcome(logPath: string, tag: string): JobOutcome {
  const status = readJobStatus(logPath, tag);
  if (status.marker && status.exitCode !== 0) {
    return { code: null, signal: null, timedOut: true };
  }
  if (status.exitCode !== null) {
    return { code: status.exitCode, signal: null };
  }
  return { code: null, signal: null, lost: true };
}

/**
 * Build the shell script that runs a job's command.
 *
 * The wrapper owns the job's deadline, so it holds whether or not pi is
 * watching. A watchdog in the background sleeps `timeoutSec`, checks that the
 * wrapper it belongs to is still alive (a reused pid must not be signalled),
 * writes `[pi-timer <tag>: timeout after Ns]`, then signals the wrapper's
 * group: TERM first, KILL after the grace, so a job that ignores TERM still
 * dies. The command runs in the foreground, so bash prints no job-status line
 * into the log, and the wrapper stops the watchdog when the command ends
 * early. The leading comment carries the tag into the process command line,
 * where a resumed process verifies the pid it read from disk. The wrapper
 * exits with the command's own status, and the `[exit N]` line it appends is
 * what a later pi reports. A deadline kill is recorded by the marker alone:
 * the group TERM ends the wrapper too, so there is no exit line to write.
 *
 * @param tag - Token that identifies this job's shell.
 * @param command - Shell command to run.
 * @param timeoutSec - Real seconds until the wrapper kills the job.
 * @returns Script for `bash -c`.
 */
export function jobScript(
  tag: string,
  command: string,
  timeoutSec: number,
): string {
  const marker = `[pi-timer ${tag}: timeout after ${timeoutSec}s]`;
  return [
    `${JOB_TAG_PREFIX}${tag}`,
    "(",
    "  escalate=0",
    "  slp=",
    // A wrapper that ended early stops the watchdog, which must not leave its
    // own sleep behind; a deadline that has passed must not let that stop it.
    `  trap 'if [ "$escalate" = 0 ]; then [ -n "$slp" ] && kill -TERM "$slp" 2>/dev/null; exit 0; fi' TERM`,
    `  sleep ${timeoutSec} &`,
    "  slp=$!",
    '  wait "$slp"',
    // A wrapper that is gone cannot be told from a reused pid by pid alone, so
    // the tag it was started with is checked before anything is signalled.
    `  ps -o command= -p $$ | grep -Fq ${shellQuote(`${JOB_TAG_PREFIX}${tag}`)} || exit 0`,
    // Committed before the marker, so a concurrent stop cannot abort the kill
    // after the log already says the deadline passed.
    "  escalate=1",
    `  printf '%s\\n' ${shellQuote(marker)}`,
    "  kill -TERM -$$",
    `  sleep ${KILL_GRACE_MS / 1000}`,
    "  kill -KILL -$$",
    ") &",
    "watchdog=$!",
    `(
${command}
)`,
    "code=$?",
    // The deadline can TERM the wrapper while it is recording the outcome; the
    // exit line is what a later report trusts, so write it before dying.
    `trap 'printf "[exit %s]\\n" "$code"; exit "$code"' TERM`,
    'kill -TERM "$watchdog" 2>/dev/null',
    'wait "$watchdog" 2>/dev/null',
    "printf '[exit %s]\\n' \"$code\"",
    'exit "$code"',
  ].join("\n");
}

/**
 * Spawn a job with its output going to `logPath`.
 *
 * `-c` rather than `-lc`, matching the built-in bash tool: a login shell would
 * print profile noise into the job log. The parent's copy of the log fd is
 * closed even when spawning throws, so the child remains the only writer.
 *
 * @param command - Shell command to run.
 * @param tag - Token that identifies this job's shell.
 * @param timeoutSec - Real seconds until the wrapper kills the job.
 * @param cwd - Directory to run in.
 * @param logPath - File that receives stdout and stderr.
 * @returns The spawned shell, a process-group leader.
 */
function spawnJob(
  command: string,
  tag: string,
  timeoutSec: number,
  cwd: string,
  logPath: string,
): ChildProcess {
  const log = openSync(logPath, "a");
  try {
    return spawn("bash", ["-c", jobScript(tag, command, timeoutSec)], {
      cwd,
      detached: true,
      stdio: ["ignore", log, log],
    });
  } finally {
    closeSync(log);
  }
}

/**
 * Take over a job started by an earlier pi process.
 *
 * Its exit is not a child event anymore, so the pid is polled; once it is gone
 * the log supplies whatever status the shell recorded. The poll is cheap and
 * does not re-verify the tag: a reused pid can delay the report, but `kill()`
 * checks the tag again before it signals anything.
 *
 * @param persisted - Job record read from the state file.
 * @param id - Timer id the job belonged to.
 * @returns A job whose `done` resolves when that process disappears.
 */
function adoptedJob(persisted: PersistedJob, id: string): Job {
  let settle: (outcome: JobOutcome) => void = () => {};
  const done = new Promise<JobOutcome>((resolve) => {
    settle = resolve;
  });
  const job: Job = { id, ...persisted, done };
  const pid = persisted.pid as number;
  const poll = setInterval(() => {
    if (pidAlive(pid)) {
      return;
    }
    clearInterval(poll);
    job.exit = recoverOutcome(persisted.logPath, persisted.tag);
    settle(job.exit);
  }, ADOPT_POLL_MS);
  poll.unref();
  return job;
}

/**
 * Describe a job that already ended before this process could watch it.
 *
 * @param persisted - Job record read from the state file.
 * @param id - Timer id the job belonged to.
 * @param outcome - What the log says, or that the status is gone.
 * @returns A job whose `done` is already resolved.
 */
function endedJob(
  persisted: PersistedJob,
  id: string,
  outcome: JobOutcome,
): Job {
  return { id, ...persisted, exit: outcome, done: Promise.resolve(outcome) };
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
  /** Session whose timers this registry owns, once a session has started. */
  private sessionId?: string;
  /** Periodic checkpoint while any timer is active. */
  private heartbeat?: NodeJS.Timeout;

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

    const startedAt = Date.now();
    const timer: Timer = {
      id,
      start: command,
      condition,
      onTick: params.onTick?.trim() || undefined,
      intervalSec: params.intervalSec ?? DEFAULT_INTERVAL_SEC,
      maxTicks: params.maxTicks ?? (command ? 0 : undefined),
      timeoutSec: params.timeoutSec ?? DEFAULT_TIMEOUT_SEC,
      startedAt,
      activeMs: 0,
      liveSince: performance.now(),
      ticksSent: 0,
      noticePending: false,
      stopped: false,
      settled: false,
      controller: new AbortController(),
    };

    this.validateBudget(timer);
    if (command) {
      timer.job = this.launch(id, command, startedAt, timer.timeoutSec, cwd);
      timer.logPath = timer.job.logPath;
    }
    this.arm(timer);
    this.persist();
    return toTimerSpec(timer);
  }

  /**
   * Start a command as its own process group, with its output going to a log.
   *
   * The child is detached into its own group so `timer_stop` or a timeout can
   * signal the whole job, and so the log fd replaces the pipes that would
   * otherwise make the exit wait on grandchildren. Detaching also lets the job
   * outlive this pi process, which is what a resumed timer re-attaches to.
   *
   * @param id - Timer id, which names the log.
   * @param command - Shell command to run.
   * @param startedAt - Spawn time, part of the log name.
   * @param timeoutSec - Real seconds until the job's shell kills it.
   * @param cwd - Directory to run in.
   * @returns The job this timer now watches.
   */
  private launch(
    id: string,
    command: string,
    startedAt: number,
    timeoutSec: number,
    cwd: string,
  ): Job {
    const logPath = jobLogPath(`${id}-${startedAt}.log`);
    const tag = randomUUID();
    const proc = spawnJob(command, tag, timeoutSec, cwd, logPath);
    // The job outlives pi, so it must not hold pi open: without this, quitting
    // waits for a job that runs until its deadline.
    proc.unref();

    const done = new Promise<JobOutcome>((resolve) => {
      proc.once("exit", (code, signal) => resolve({ code, signal }));
      proc.once("error", (error) =>
        resolve({ code: null, signal: null, error: String(error) }),
      );
    });
    const job: Job = { id, logPath, startedAt, tag, pid: proc.pid, proc, done };
    void done.then((outcome) => {
      job.exit = outcome;
    });
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
   * Stop a job: stop and expiry both come through here.
   *
   * The wake that would report the exit is suppressed for a stop, since the
   * caller already told the agent. The log still records who ended it, for a
   * reader that arrives after the session is gone. The group is signalled even
   * when the leader has already exited, so a command's own background children
   * do not outlive a timeout or a stop.
   *
   * A job restored from disk is signalled only after its tag confirms the pid
   * is still that job, so a reboot that reused the pid cannot make a timer kill
   * a stranger's process group.
   *
   * @param job - Job to kill.
   * @param marker - How the log should say it ended.
   * @returns Whether a signal was sent, so the caller only waits for an exit
   *   that this timer caused.
   */
  private kill(job: Job, marker: string): boolean {
    const { pid } = job;
    if (pid === undefined || job.exit) {
      return false;
    }
    if (!job.proc && !jobAlive(pid, job.tag)) {
      return false;
    }
    signalGroup(pid, "SIGTERM");
    const escalate = setTimeout(
      () => signalGroup(pid, "SIGKILL"),
      KILL_GRACE_MS,
    );
    escalate.unref();
    // A group that ended before the grace period must not be signalled again
    // under a pid the system may have since reused.
    void job.done.then(() => clearTimeout(escalate));
    void job.done.then(() => appendLogMarker(job.logPath, marker));
    return true;
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
   * @returns The cancelled timer and whether its job was signalled, or
   *   `undefined` when nothing had that id.
   */
  stop(id: string): { timer: Timer; signalled: boolean } | undefined {
    const timer = this.timers.get(id);
    if (!timer) {
      return undefined;
    }

    timer.stopped = true;
    timer.controller.abort();
    let signalled = false;
    if (timer.job) {
      signalled = this.kill(timer.job, "killed by timer_stop");
      this.jobs.delete(id);
    }
    this.retire(
      toTimerSpec(timer),
      "killed by timer_stop",
      "killed",
      durationText(ageMs(timer)),
      timer,
    );
    return { timer, signalled };
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
    this.persist();
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
   * `close()` uses this at shutdown, where the jobs must outlive the process.
   * `restore()` uses it too and then re-arms what the new timeline still has; a
   * job that nothing re-arms is killed there, not here.
   */
  stopAll(): void {
    for (const timer of this.timers.values()) {
      timer.stopped = true;
      timer.controller.abort();
    }
    this.timers.clear();
    this.retired.clear();
    this.stopHeartbeat();
  }

  /**
   * Stop watching for the end of the session and save what is still running.
   *
   * Jobs are deliberately left running: the next pi process resumes the same
   * timers from the state file and re-attaches them, which is what makes a
   * timer outlive a reload, a restart, or a reboot.
   */
  close(): void {
    this.checkpoint();
    this.stopAll();
  }

  /**
   * Write the active timers to this session's state file.
   *
   * Called on every change and by the heartbeat, so a crash loses at most one
   * checkpoint interval of pi-live time; a graceful shutdown checkpoints
   * exactly. A session with no active timer drops its file, so a later resume
   * cannot resurrect anything.
   */
  private persist(): void {
    if (!this.sessionId) {
      return;
    }
    const path = timerStatePath(this.sessionId);
    const timers = [...this.timers.values()].map((timer) =>
      this.persisted(timer),
    );
    if (timers.length === 0) {
      rmSync(path, { force: true });
      this.stopHeartbeat();
      return;
    }
    const state: TimerStateFile = {
      version: STATE_VERSION,
      sessionId: this.sessionId,
      updatedAt: Date.now(),
      timers,
    };
    mkdirSync(dirname(path), { recursive: true });
    // Written beside the target and renamed, so a crash mid-write leaves the
    // previous state readable instead of half a file. The pid keeps two pi
    // processes on one session from tearing each other's temp file.
    const temp = `${path}.${process.pid}.tmp`;
    writeFileSync(temp, `${JSON.stringify(state, null, 2)}\n`);
    renameSync(temp, path);
    this.startHeartbeat();
  }

  /**
   * Snapshot every timer's pi-live time and write the state file.
   *
   * The checkpoint folds the current process's monotonic time into `activeMs`
   * and restarts the live window, so a later process can resume the budget
   * without counting the outage.
   */
  private checkpoint(): void {
    const now = performance.now();
    for (const timer of this.timers.values()) {
      timer.activeMs = liveMs(timer);
      timer.liveSince = now;
    }
    this.persist();
  }

  /**
   * Describe one timer as the state file stores it.
   *
   * @param timer - Timer to serialize.
   * @returns Its specification plus the runtime state a resume needs.
   */
  private persisted(timer: Timer): PersistedTimer {
    const { job } = timer;
    return {
      ...toTimerSpec(timer),
      activeMs: liveMs(timer),
      ticksSent: timer.ticksSent,
      // A job whose spawn never produced a pid is still recorded: on resume it
      // reports why it has no process instead of waiting out a phantom timer.
      job: job && {
        pid: job.pid,
        logPath: job.logPath,
        startedAt: job.startedAt,
        tag: job.tag,
      },
    };
  }

  /** Checkpoint periodically while a timer is active. */
  private startHeartbeat(): void {
    if (this.heartbeat) {
      return;
    }
    this.heartbeat = setInterval(() => this.checkpoint(), CHECKPOINT_MS);
    this.heartbeat.unref();
  }

  /** Stop the checkpoint loop once nothing is left to save. */
  private stopHeartbeat(): void {
    if (!this.heartbeat) {
      return;
    }
    clearInterval(this.heartbeat);
    this.heartbeat = undefined;
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
      ? `job pid ${timer.job.pid ?? "?"}, log ${timer.job.logPath}`
      : timer.condition
        ? `cond: ${timer.condition}`
        : "timer, no condition";
    return {
      id: timer.id,
      state: "running",
      age: durationText(ageMs(timer)),
      ticks: `ticks ${ticks}`,
      target,
      spec: toTimerSpec(timer),
      pid: timer.job?.pid,
    };
  }

  /**
   * Rebuild the active timers when a session starts or its branch changes.
   *
   * A started session reads its state file: that record is newer than the
   * transcript and is the only place a live job and the pi-live elapsed time
   * are kept, so a restart resumes the budget instead of spending it. A branch
   * change always follows the branch it is given, carrying over the runtime
   * state of the timers that survive the switch.
   *
   * A branched session (`/fork`, `/clone`, `--fork`) is the one transcript that
   * does not bring timers along: it copies what another session said, not the
   * work behind it, so replaying the timers there would duplicate wakes and
   * report jobs it never started. Such a session's header names its parent.
   *
   * A resumed timer is state, not news: the user hears about it in a toast and
   * `/timers`, while the model only learns about a timer when one of its own
   * wakes arrives. That keeps a reload from adding a status line to the
   * conversation every time, and a wake already says what happened.
   *
   * @param ctx - Context of the session that is starting or switching.
   * @param source - `session_start` reads the state file; `session_tree` uses
   *   the branch alone.
   * @param reason - Why the session started, when `source` is `session_start`.
   *   A reload keeps the same session and the same pi process, so it has
   *   nothing to tell the user about.
   */
  async restore(
    ctx: ExtensionContext,
    source: "session_start" | "session_tree",
    reason?: SessionStartEvent["reason"],
  ): Promise<void> {
    // Snapshot before `stopAll()` clears the map: a branch switch re-arms some
    // of these ids and must not restart their budget or their tick count.
    const carried = new Map(this.timers);
    this.sessionId = ctx.sessionManager.getSessionId();
    this.stopAll();

    const state =
      source === "session_start" ? readTimerState(this.sessionId) : undefined;
    if (state) {
      const resumed = await this.restoreState(state.timers);
      if (resumed > 0 && reason !== "reload") {
        ctx.ui.notify(
          `Resumed ${resumed} timer${resumed === 1 ? "" : "s"} from before this pi start.`,
          "info",
        );
      }
      return;
    }
    if (
      source === "session_start" &&
      ctx.sessionManager.getHeader()?.parentSession
    ) {
      return;
    }
    this.restoreBranch(ctx.sessionManager.getBranch(), carried);
    // A timer the branch no longer has leaves its job behind: no deadline, no
    // wake, and nobody who could ever adopt it again. The branch dropped the
    // timer, so it drops the work too.
    for (const [id, job] of this.jobs) {
      if (!this.timers.has(id)) {
        this.kill(job, "killed when its timer left the branch");
        this.jobs.delete(id);
      }
    }
    this.persist();
  }

  /**
   * Arm the timers a state file recorded.
   *
   * A job is re-attached when its process is still the one this timer started;
   * otherwise it ended while pi was not running, and the session gets one wake
   * reporting what its log holds. Timers that never had a job simply continue
   * with the budget they had left.
   *
   * Everything that lives is armed before any wake is sent, so the state file
   * is complete again before a slow callback can delay startup. A job that
   * ended while pi was away is still news the timer owed the agent, so it
   * arrives as a real wake; a timer that merely kept running says nothing
   * until its own next wake.
   *
   * @param timers - Timer records read from the state file.
   * @returns How many timers resumed.
   */
  private async restoreState(
    timers: readonly PersistedTimer[],
  ): Promise<number> {
    const ended: { timer: Timer; job: Job; outcome: JobOutcome }[] = [];
    let resumed = 0;
    for (const entry of timers) {
      const timer = this.timerFromState(entry);
      const persisted = entry.job;
      const alive =
        persisted?.pid !== undefined && jobAlive(persisted.pid, persisted.tag);
      if (persisted && !alive) {
        const outcome = recoverOutcome(persisted.logPath, persisted.tag);
        ended.push({
          timer,
          job: endedJob(persisted, entry.id, outcome),
          outcome,
        });
        continue;
      }
      if (persisted) {
        timer.job = adoptedJob(persisted, entry.id);
        this.jobs.set(entry.id, timer.job);
      }
      this.arm(timer);
      resumed += 1;
    }
    this.persist();

    for (const { timer, job, outcome } of ended) {
      timer.job = job;
      // `finish` retires the timer, and its ownership guard only retires one
      // that is in the map.
      this.timers.set(timer.id, timer);
      if (outcome.timedOut) {
        await this.finish(
          timer,
          "timeout",
          `timeout after ${timer.timeoutSec}s; job killed`,
          "timed out",
        );
        continue;
      }
      const end = describeJobEnd(
        outcome,
        durationText(Date.now() - job.startedAt),
      );
      await this.finish(timer, jobEndState(outcome), end.line, end.reason);
    }
    return resumed;
  }

  /**
   * Build a timer from a state record.
   *
   * @param entry - Record read from the state file.
   * @returns A timer with the recorded budget and tick count, armed now.
   */
  private timerFromState(entry: PersistedTimer): Timer {
    const { activeMs, ticksSent, job: _job, ...spec } = entry;
    return {
      ...spec,
      activeMs,
      liveSince: performance.now(),
      ticksSent,
      noticePending: false,
      stopped: false,
      settled: false,
      controller: new AbortController(),
    };
  }

  /**
   * Arm the timers recorded on a session branch.
   *
   * A job entry replayed from the transcript is never spawned or signalled
   * again: it either matches a job this process still runs, or it belonged to
   * an earlier pi process and only its log is left. A timer that survives a
   * branch switch keeps the budget it had already spent.
   *
   * @param entries - Active session branch entries.
   * @param carried - Timers that were active before the switch, by id.
   */
  private restoreBranch(
    entries: readonly SessionEntry[],
    carried: ReadonlyMap<string, Timer>,
  ): void {
    for (const spec of collectActiveTimers(entries).values()) {
      const job = spec.start ? this.jobs.get(spec.id) : undefined;
      if (spec.start && !job) {
        const log = spec.logPath ? `; log ${spec.logPath}` : "";
        // Its end was never observed, so it can only be reported as failed.
        this.retire(
          spec,
          `orphaned${log}`,
          "failed",
          durationText(Date.now() - spec.startedAt),
        );
        continue;
      }
      const previous = carried.get(spec.id);
      this.arm({
        ...spec,
        // A live job for this id is what this process actually runs, so it owns
        // the start time, the log and the age the wake reports.
        startedAt: job?.startedAt ?? spec.startedAt,
        logPath: job?.logPath ?? spec.logPath,
        activeMs: previous ? liveMs(previous) : 0,
        liveSince: performance.now(),
        ticksSent: previous?.ticksSent ?? 0,
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
            durationText(ageMs(timer)),
            timer,
          );
          void this.notify(
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
   * Milliseconds left of the timer's pi-live budget.
   *
   * Only a timer without a job uses this: its schedule runs while pi does, so
   * time while pi is closed does not spend it.
   *
   * @param timer - Timer to check.
   * @returns Remaining milliseconds; zero or less means the deadline is past.
   */
  private remainingMs(timer: Timer): number {
    return timer.timeoutSec * 1000 - liveMs(timer);
  }

  /**
   * Milliseconds until the registry's last-resort job deadline cleanup.
   *
   * A job's own shell kills it at `timeoutSec` of real time, whether or not pi
   * is watching. This is later by the wrapper's KILL grace plus a margin, so
   * it only fires when that shell is gone or broken, and it is based on the
   * spawn time so a job resumed past its deadline is killed at once.
   *
   * @param timer - Job timer to check.
   * @returns Remaining milliseconds; zero or less means the backstop is due.
   */
  private backstopMs(timer: Timer): number {
    const startedAt = timer.job?.startedAt ?? timer.startedAt;
    return (
      startedAt + timer.timeoutSec * 1000 + JOB_BACKSTOP_SLACK_MS - Date.now()
    );
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
    if (timer.condition && (await this.matches(timer, timer.condition))) {
      await this.finish(
        timer,
        "done",
        this.conditionLine(timer),
        "condition met",
      );
      return;
    }

    while (!timer.stopped) {
      const waitMs = Math.min(
        timer.intervalSec * 1000,
        this.remainingMs(timer),
      );
      if (waitMs > 0) {
        await sleep(Math.min(waitMs, MAX_TIMEOUT_MS), undefined, {
          signal: timer.controller.signal,
        });
      }
      if (timer.stopped) {
        return;
      }

      if (this.remainingMs(timer) <= 0) {
        await this.finish(
          timer,
          "timeout",
          `timeout after ${timer.timeoutSec}s`,
          "timed out",
        );
        return;
      }

      if (timer.condition && (await this.matches(timer, timer.condition))) {
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
      await this.tick(timer, body, last);
      if (last) {
        // The tick just sent was the timer's farewell.
        this.retire(
          toTimerSpec(timer),
          "tick budget spent",
          "done",
          durationText(ageMs(timer)),
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
    return `condition met after ${durationText(ageMs(timer))}: ${timer.condition}`;
  }

  /**
   * Watch a background job until it exits, is killed, its condition holds, or
   * its deadline passes.
   *
   * The exit is an event, so no poll interval decides how soon that wake
   * arrives; `intervalSec` paces optional progress ticks and condition checks,
   * and a job timer without either waits on the exit alone. A job adopted from
   * a previous pi process has no exit event, so its pid is polled instead. The
   * deadline belongs to the job's own shell; this loop only adds the backstop
   * for a shell that could not end the job itself.
   *
   * @param timer - Timer whose `job` owns the process.
   */
  private async watch(timer: Timer): Promise<void> {
    const job = timer.job as Job;
    // Captured once: a job that exits as the deadline passes still has an exit
    // code to report, which is better news than "killed".
    let outcome: JobOutcome | undefined;
    void job.done.then((result) => {
      outcome = result;
    });

    // A condition can test state outside the job, so every timer checks it
    // immediately and then at each interval, whether or not `start` is set.
    if (await this.conditionHeld(timer)) {
      await this.finishConditionJob(timer, job);
      return;
    }

    while (!timer.stopped && !timer.settled) {
      const paced = this.canTick(timer) || timer.condition !== undefined;
      const remaining = Math.round(this.backstopMs(timer));
      const waitMs = paced
        ? Math.max(0, Math.min(timer.intervalSec * 1000, remaining))
        : Math.max(0, remaining);
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
      // The job's shell should have killed it by now; only a broken or missing
      // wrapper reaches this. A condition that holds right now is still the
      // better news, so it is checked once more before the expiry.
      if (this.backstopMs(timer) <= 0) {
        if (await this.conditionHeld(timer)) {
          await this.finishConditionJob(timer, job);
          return;
        }
        await this.expireJob(timer, job);
        return;
      }
      await this.tickJob(timer, job);
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
   * Check the condition and send one progress tick while a job runs.
   *
   * Matches a periodic timer: the callback runs even when its wake is
   * throttled, and a dropped wake costs no tick budget. A condition that holds
   * ends the timer and takes the job with it, like a `timer_stop`.
   *
   * @param timer - Job timer to tick.
   * @param job - Job the timer watches.
   */
  private async tickJob(timer: Timer, job: Job): Promise<void> {
    if (await this.conditionHeld(timer)) {
      await this.finishConditionJob(timer, job);
      return;
    }

    const body = await this.capture(timer);
    if (timer.stopped || timer.noticePending || !this.canTick(timer)) {
      return;
    }
    await this.tick(timer, body, false);
  }

  /**
   * End a job timer whose condition held, killing the job it watches.
   *
   * A timer owns the job it started, so ending the timer must not leave the
   * process running with nobody watching it. The log records the reason as
   * `killed after condition met`.
   *
   * @param timer - Job timer whose condition held.
   * @param job - Job to kill.
   */
  private async finishConditionJob(timer: Timer, job: Job): Promise<void> {
    await this.endJob(
      timer,
      job,
      "killed after condition met",
      "done",
      this.conditionLine(timer),
      "condition met",
    );
  }

  /**
   * End a job timer whose backstop deadline passed, killing the job it watches.
   *
   * The job's own shell normally ends it at the deadline; this is the cleanup
   * for a shell that could not, so a job nobody watches cannot keep running
   * past its deadline.
   *
   * @param timer - Job timer whose backstop deadline passed.
   * @param job - Job to kill.
   */
  private async expireJob(timer: Timer, job: Job): Promise<void> {
    await this.endJob(
      timer,
      job,
      "killed by the timer",
      "timeout",
      `timeout after ${timer.timeoutSec}s; job killed`,
      "timed out",
    );
  }

  /**
   * Kill a job and finish its timer with the given news.
   *
   * A job that already exited keeps its own exit status: killing it now would
   * add a misleading marker and replace the real outcome with a timeout or a
   * condition that happened at the same moment.
   *
   * @param timer - Timer ending.
   * @param job - Job to kill unless it already exited.
   * @param marker - How the log should say the timer ended it.
   * @param state - How the timer ended, for its wake and `/timers` marker.
   * @param line - News for the wake.
   * @param reason - Short reason a later `timer_stop` reports.
   */
  private async endJob(
    timer: Timer,
    job: Job,
    marker: string,
    state: "done" | "timeout",
    line: string,
    reason: string,
  ): Promise<void> {
    if (job.exit) {
      await this.finishJob(timer, job, job.exit);
      return;
    }
    // Out of `jobs` first: a `restore()` during the grace window must not
    // re-attach a job this loop is already killing.
    this.jobs.delete(job.id);
    if (!this.kill(job, marker)) {
      // Nothing was signalled: an adopted job ended between two polls, or its
      // pid no longer carries the tag. Either way this timer is not the one
      // that ended it, so the job's own record is the news.
      const outcome =
        job.proc === undefined
          ? recoverOutcome(job.logPath, job.tag)
          : await job.done;
      await this.finishJob(timer, job, outcome);
      return;
    }
    await job.done;
    if (timer.stopped) {
      return;
    }
    await this.finish(timer, state, line, reason);
  }

  /**
   * Report a job that ended by itself, with its exit status and log tail.
   *
   * The job shell already wrote its own `[exit N]` marker, so nothing is added
   * to the log here; a job that ended while pi was away has no status to add.
   * A deadline kill is reported as a timeout, not as the signal it looks like.
   *
   * @param timer - Timer that watched the job.
   * @param job - Job that ended.
   * @param outcome - Exit code, signal, spawn failure, or an unobserved end.
   */
  private async finishJob(
    timer: Timer,
    job: Job,
    outcome: JobOutcome,
  ): Promise<void> {
    this.jobs.delete(job.id);
    // The deadline is the job's own shell's doing, so it is a timeout even
    // though the process was signalled.
    if (endedByDeadline(job, outcome)) {
      await this.finish(
        timer,
        "timeout",
        `timeout after ${timer.timeoutSec}s; job killed`,
        "timed out",
      );
      return;
    }
    // Wall-clock since the spawn is how long the job actually ran: it kept
    // running while pi did not.
    const end = describeJobEnd(
      outcome,
      durationText(Date.now() - job.startedAt),
    );
    // A job the shell exited wrote its own marker; one a signal from outside
    // the timer ended has no shell left to write it.
    if (outcome.signal) {
      appendLogMarker(job.logPath, `killed by ${outcome.signal}`);
    }
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
   * Prefix a callback with the job output on its stdin.
   *
   * The job log is the command's stdout and stderr, so reading it directly
   * avoids copying a log that may have grown for hours. A timer without a job
   * has no output to feed and returns the command unchanged. A missing log is
   * not an error: the callback runs with the empty stdin the shell already has.
   *
   * @param timer - Timer whose callback is about to run.
   * @param command - Shell command to run.
   * @returns The command, with stdin redirected from the job log when present.
   */
  private withJobInput(timer: Timer, command: string): string {
    const logPath = timer.job?.logPath;
    if (!logPath) {
      return command;
    }
    return `{ exec 0<${shellQuote(logPath)}; } 2>/dev/null; ${command}`;
  }

  /**
   * Whether a timer's condition holds now.
   *
   * @param timer - Timer to check.
   * @returns `true` when the timer has a condition and it exited 0.
   */
  private async conditionHeld(timer: Timer): Promise<boolean> {
    const condition = timer.condition;
    if (!condition) {
      return false;
    }
    return this.matches(timer, condition);
  }

  /**
   * Run the timer's condition.
   *
   * @param timer - Timer the condition belongs to.
   * @param condition - Shell predicate to evaluate.
   * @returns `true` when the condition exited 0.
   */
  private async matches(timer: Timer, condition: string): Promise<boolean> {
    const remaining = timer.job
      ? this.backstopMs(timer)
      : this.remainingMs(timer);
    const result = await this.pi.exec(
      "bash",
      ["-lc", this.withJobInput(timer, condition)],
      {
        signal: timer.controller.signal,
        timeout: Math.min(
          MAX_CONDITION_TIMEOUT_MS,
          Math.max(MIN_CONDITION_TIMEOUT_MS, remaining),
        ),
      },
    );
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
  private async tick(timer: Timer, body: string, last: boolean): Promise<void> {
    timer.ticksSent += 1;
    // The tick count is what a resumed timer continues from, so it outlives a
    // crash even when the next heartbeat would have come later.
    this.persist();
    const count = `${timer.ticksSent}${timer.maxTicks === undefined ? "" : `/${timer.maxTicks}`}`;
    // A last tick carries the farewell, so the one wake the agent reads tells it
    // both the news and that the timer is gone.
    const ending = last ? "; timer stopped" : "";
    await this.notify(
      timer,
      "tick",
      `tick ${count}, ${durationText(ageMs(timer))} elapsed${ending}`,
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
   * @returns Wake-ready output, or an empty string when no callback is set.
   */
  private async capture(timer: Timer): Promise<string> {
    if (!timer.onTick) {
      return "";
    }

    try {
      const result = await this.pi.exec(
        "bash",
        ["-lc", this.withJobInput(timer, timer.onTick)],
        {
          signal: timer.controller.signal,
          timeout: ON_TICK_TIMEOUT_MS,
        },
      );
      const output = `${result.stdout}${result.stderr}`;
      const note = result.truncated
        ? "[onTick output was cut at Pi's command buffer limit]"
        : result.killed
          ? `[onTick output was cut short by the ${ON_TICK_TIMEOUT_MS / 1000}s timeout]`
          : "";
      return note ? `${output}${output ? "\n\n" : ""}${note}` : output;
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
      durationText(ageMs(timer)),
      timer,
    );
    const tail = timer.job ? readLogTail(timer.job.logPath) : "";
    const body = await this.capture(timer);
    if (timer.stopped) {
      return;
    }
    await this.notify(timer, state, `${line}; timer stopped`, body, tail);
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
   * @param body - Optional `onTick` output to format and carry.
   * @param tail - Optional job-log tail to put before the callback output.
   */
  private async notify(
    timer: Timer,
    state: TimerState,
    line: string,
    body = "",
    tail = "",
  ): Promise<void> {
    if (timer.stopped) {
      return;
    }
    const captured = body
      ? await formatCallbackOutput(timer.id, body)
      : { text: "" };
    if (timer.stopped) {
      if (captured.savedPath) {
        await rm(captured.savedPath, { force: true });
      }
      return;
    }
    timer.noticePending = true;
    // A blank line keeps the captured output its own block instead of letting a
    // log line continue the summary paragraph.
    const parts = [tail, captured.text].filter(Boolean).join("\n");
    const content = parts
      ? `[timer ${timer.id}] ${line}\n\n${parts}`
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
        ? spec.onTick
          ? "no tick wakes (onTick runs at exit)"
          : "no tick wakes"
        : `tick wakes every ${spec.intervalSec}s`;
    const ending = spec.condition
      ? `wakes you when it exits, when the condition first exits 0 (which kills the job), or after ${spec.timeoutSec}s of real time`
      : `wakes you when it exits or after ${spec.timeoutSec}s of real time`;
    return `Started job "${spec.id}": runs \`${spec.start}\` in the background, ${ticks}, log ${spec.logPath}; ${ending}. Its own shell kills it at that deadline, even while pi is closed; it is re-attached when you resume this session, and only \`timer_stop\` or the deadline ends it.`;
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
    ? `it ends when the condition first exits 0 or after ${spec.timeoutSec}s of running time`
    : `it ends after that tick or at its ${spec.timeoutSec}s budget of running time`;
  return `Started "${spec.id}": ${ticks}; ${ending}. Wakes arrive even after you end your turn; time while pi is closed does not count against that budget, and resuming the session resumes the timer.`;
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
      "Start a background command, wait for a condition, tick on a schedule, or combine them; every call returns immediately and wakes you later. Pass `start` with `condition` and/or `onTick` to start and monitor one job in one call. Timers survive pi restarts, reloads, and reboots: resuming the session re-arms them and re-attaches a running job. For a `start` job, `timeoutSec` is real time and the job's own shell kills it at that deadline even while pi is closed; without a job, `timeoutSec` is a budget of running time. `timer_stop` also kills a job.",
    promptSnippet:
      "Start a background command and wake when it exits, wait for a condition, or tick periodically -- in any combination.",
    promptGuidelines: [
      "For a command that may take a while, use `timer_start` with `start`, never bash `&`, pid or exit files, polling, or `sleep N`. Pass `condition`/`onTick` in the same call to monitor it. Keep working or end your turn: an idle agent is woken in a new turn.",
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
      const logPath = stopped?.timer.job?.logPath;
      const killed = stopped?.signalled
        ? `; killed its job, log ${logPath}`
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
   * @returns One width-truncated line per timer, the selected row on the
   *   selection background.
   */
  private renderRows(
    rows: readonly TimerRow[],
    width: number,
    selected: number,
  ): string[] {
    const { theme } = this;
    const widths = timerWidths(rows);
    const inner = Math.max(0, width - PAGE_PADDING_X * 2);
    return rows.map((row, index) =>
      listRow(
        theme,
        padRight(row.id, widths.id),
        [
          this.spinner.marker(row.state, theme),
          theme.fg("muted", padRight(row.state, widths.state)),
          theme.fg("muted", padRight(row.age, widths.age)),
          theme.fg("dim", padRight(row.ticks, widths.ticks)),
          theme.fg("dim", row.target),
        ],
        inner,
        index === selected,
      ),
    );
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
      "Report every active timer: id, age, ticks spent and what it waits for. Name an id to report just that timer.",
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

  pi.on("session_start", async (event, ctx) => {
    await registry.restore(ctx, "session_start", event.reason);
  });

  pi.on("session_tree", async (_event, ctx) => {
    await registry.restore(ctx, "session_tree");
  });

  // Any tool call means the agent acted on the last wake, so the next tick may
  // be delivered again. `agent_start` covers runs that begin without a tool.
  pi.on("tool_call", async () => registry.clearPending());
  pi.on("agent_start", async () => registry.clearPending());
  // Jobs keep running for the next pi process to re-attach; only the loops and
  // the checkpoint belong to this one. `close()` saves the elapsed time, so a
  // graceful quit does not even lose the time since the last heartbeat.
  pi.on("session_shutdown", async () => registry.close());
}
