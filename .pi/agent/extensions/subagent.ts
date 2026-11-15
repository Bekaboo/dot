/**
 * Subagent tool.
 *
 * `subagent()` spawns a separate `pi --mode rpc` process for a self-contained
 * task, returns as soon as the child is running, and injects a
 * `[subagent <id>]` message into this session when the child finishes. The
 * child gets a fresh context window; its prompt, tools, model and working
 * directory are chosen per call. It keeps its own session file under
 * `<agent-dir>/subagent-sessions/`, so its transcript outlives the process.
 *
 * RPC mode, rather than a single-shot print mode, is what lets a child use
 * async tools: its prompt travels on stdin and the process survives a turn
 * with no tool calls, so background work that reports afterwards, such as a
 * nested subagent, still wakes it. Since the process has no natural end any
 * more, the child's own instance of this extension ends it when the model calls
 * the `subagent_finish` tool.
 *
 * Results are queued through pi as soon as the child exits: a busy parent
 * receives them at the next turn boundary, and an idle parent starts a turn.
 * Child callbacks never retain a tool context; shutdown drops late results.
 */

import { type ChildProcess, spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
import type { StopReason } from "@earendil-works/pi-ai";
import {
  type ExtensionAPI,
  type ExtensionCommandContext,
  type ExtensionContext,
  getAgentDir,
  type JsonAgentSessionEvent,
  type KeybindingsManager,
  type SessionEntry,
  type SessionStartEvent,
  type Theme,
  type ToolDefinition,
} from "@earendil-works/pi-coding-agent";
import {
  type Component,
  type TUI,
  truncateToWidth,
  visibleWidth,
} from "@earendil-works/pi-tui";
import { Type } from "typebox";
import {
  deliverWake,
  releaseIdleWake,
  type WakeSession,
} from "./utils/idle-wake.ts";
import {
  DrillDown,
  listRow,
  OverlayPage,
  padLeft,
  padRight,
  SELECTED_CURSOR,
} from "./utils/overlay.ts";
import {
  PAGE_PADDING_X,
  VIEWPORT_RESERVE_ROWS,
  windowStart,
} from "./utils/page.ts";
import { type RunState, Spinner } from "./utils/spinner.ts";

export {
  DEFAULT_TIMEOUT_SEC,
  MAX_RECORD_BYTES,
  SELECTED_CURSOR,
  VIEWPORT_RESERVE_ROWS,
};

/** Custom message type used for subagent notifications. */
const NOTICE_TYPE = "subagent";

/**
 * Environment variable that marks a pi process as a spawned subagent.
 *
 * The child's copy of this extension reads it to take over ending the process;
 * a session a user drives must never end itself that way.
 */
const CHILD_ENV = "PI_SUBAGENT_CHILD";

/**
 * Directory under the agent dir holding the children's session files.
 *
 * A sibling of `sessions/`, never a part of it, so `/resume` never offers a
 * child as a chat.
 */
const SUBAGENT_SESSION_DIR = "subagent-sessions";

/**
 * Custom session entry that records one subagent run.
 *
 * The parent's session is the run's only durable home: an entry is appended
 * when the run starts, pauses and ends, so a pi that restarts can pick the
 * paused ones up again.
 */
const RUN_ENTRY = "subagent-run";

/**
 * Prompt a child that reopens its own session after a restart.
 *
 * Its transcript above is its own work, so the message only says what happened
 * and where to continue; describing the task again would restart it.
 */
const RESUME_MESSAGE =
  "This is a continuation after a restart: the session that spawned you was closed and has resumed you. Your transcript above is your own finished work. Continue the task from where it stopped, without repeating steps that are already done, and call `subagent_finish` with your final answer when it is complete.";

/**
 * Lifecycle of a run as its session record states it.
 *
 * `paused` is a run the parent stopped on purpose and will resume; `running`
 * left behind at a restart means the pi process died without pausing it.
 */
type RunRecordState =
  | "running"
  | "paused"
  | "done"
  | "failed"
  | "timeout"
  | "killed";

/** One line of the session's record of a run, replayed after a restart. */
interface RunRecord {
  id: string;
  state: RunRecordState;
  /** Model as requested, empty when the child inherits pi's default. */
  model: string;
  /** Thinking level forced on the child, empty to inherit. */
  thinking: string;
  /** Tools as requested, empty when the child gets pi's defaults. */
  tools: string[];
  cwd: string;
  /** Wall-clock limit the child was given, in seconds of running time. */
  timeoutSec: number;
  /** Running time already spent before this record, in ms. */
  elapsedMs: number;
  /** When the run first started, in ms, so the overlay keeps its order. */
  startedAt: number;
  /** Creation order across restarts. */
  order: number;
  /** The child's own pi session id: the handle a resume opens. */
  childSessionId: string;
  /**
   * Session id of the parent that owns the run.
   *
   * A fork copies the source session's entries under a new id, so this is what
   * stops a forked branch from respawning another session's children.
   */
  owner: string;
}

/** What starting a run needs, fresh or resumed. */
interface StartRequest {
  id: string;
  prompt: string;
  model: string;
  thinking: string;
  tools: string[];
  cwd: string;
  timeoutSec: number;
}

/** Id of the `prompt` command sent to the child, echoed in its response. */
const PROMPT_ID = "prompt";

/** Id of the `get_state` command that asks the child where its transcript is. */
const STATE_ID = "state";

/**
 * Tool a spawned child uses to end its session by itself.
 *
 * Named rather than inlined: the child asserts it at session start, and its
 * system prompt tells the model when to call it.
 */
const FINISH_TOOL = "subagent_finish";

/** Environment variable pi-intercom publishes when a session starts with it loaded. */
const INTERCOM_SESSION_ID_ENV = "PI_INTERCOM_SESSION_ID";

/*
 * Environment pi-intercom reads to give a spawned child a tool that reaches
 * back to its supervisor.
 *
 * These are facts about this session, not a link to an extension: nothing reads
 * them unless something is installed that understands them, so an environment
 * without pi-intercom is unaffected. A bridge is ignored whole unless the
 * target, run id, agent and index are all present; the session id and the
 * intercom name are optional refinements.
 */
const ORCHESTRATOR_TARGET_ENV = "PI_SUBAGENT_ORCHESTRATOR_TARGET";
const ORCHESTRATOR_SESSION_ID_ENV = "PI_SUBAGENT_ORCHESTRATOR_SESSION_ID";
const CHILD_RUN_ID_ENV = "PI_SUBAGENT_RUN_ID";
const CHILD_AGENT_ENV = "PI_SUBAGENT_CHILD_AGENT";
const CHILD_INDEX_ENV = "PI_SUBAGENT_CHILD_INDEX";
const CHILD_INTERCOM_NAME_ENV = "PI_SUBAGENT_INTERCOM_SESSION_NAME";

/** Every variable the bridge above is made of, for clearing it as a whole. */
const BRIDGE_ENV = [
  ORCHESTRATOR_TARGET_ENV,
  ORCHESTRATOR_SESSION_ID_ENV,
  CHILD_RUN_ID_ENV,
  CHILD_AGENT_ENV,
  CHILD_INDEX_ENV,
  CHILD_INTERCOM_NAME_ENV,
];

/**
 * Environment variable a pi-subagents run uses to hand its child a supervisor
 * channel of its own.
 *
 * That channel belongs to this session, not to the one this session spawns, and
 * pi-intercom reads it as "the bridge is already taken care of".
 */
const SUPERVISOR_CHANNEL_ENV = "PI_SUBAGENT_SUPERVISOR_CHANNEL_DIR";

/**
 * Environment that describes this process's own coordination and must not reach
 * the child it spawns.
 *
 * A child gets the bridge computed for it or none at all, and never this
 * session's identity or an outer run's channel: it belongs to the session that
 * spawned it, so a grandchild must never end up addressing the run above.
 */
const NOT_INHERITED_ENV = [
  INTERCOM_SESSION_ID_ENV,
  SUPERVISOR_CHANNEL_ENV,
  ...BRIDGE_ENV,
];

/** How much of the child's final answer to put in a notification, in bytes. */
const OUTPUT_CAP_BYTES = 16 * 1024;

/** How much of the child's stderr to keep for a failure report, in bytes. */
const STDERR_CAP_BYTES = 2 * 1024;

/** Grace period before a child that ignored SIGTERM gets SIGKILL, in ms. */
const KILL_GRACE_MS = 2_000;

/** Largest delay `setTimeout` honors; anything above it would fire at once. */
const MAX_SET_TIMEOUT_MS = 2 ** 31 - 1;

/**
 * Longest timeout a child may get, in seconds.
 *
 * Both the parent's deadline and the child's warning are single `setTimeout`
 * calls, so a limit beyond what one can hold would fire at once instead.
 */
const MAX_TIMEOUT_SEC = Math.floor(MAX_SET_TIMEOUT_MS / 1000);

/**
 * How long a child may take to start its run before the call gives up, in ms.
 *
 * The child ends itself once its work is done, so a child that never starts a
 * run -- its extensions failed to load, or an extension consumed the prompt --
 * would otherwise stay alive forever and never report.
 */
const START_TIMEOUT_MS = 60_000;

/**
 * Wall-clock limit for a child when the caller names none, in seconds.
 *
 * Be conservative because a subagent tend to over-think and run for a long
 * time if given too much time to complete.
 */
const DEFAULT_TIMEOUT_SEC = 600;

/** Environment variable carrying a child's timeout, so it can warn itself. */
const TIMEOUT_ENV = "PI_SUBAGENT_TIMEOUT_SEC";

/** Fraction of its timeout after which a child is warned to wrap up. */
const TIMEOUT_WARN_THRESH = 0.9;

/**
 * Shortest warning lead worth a model turn, in seconds.
 *
 * A percentage of a short timeout would land too close to the deadline to be
 * useful, so the warning moves earlier instead.
 */
const MIN_TIMEOUT_WARN_LEAD_SEC = 10;

/**
 * System-prompt lines every spawned child gets.
 *
 * These describe the child's role and its deadline, which belong in the system
 * prompt rather than a tool declaration: a child must know what it is and how
 * long the parent lets it run before the session is cut off. They are appended
 * verbatim via `--append-system-prompt`.
 *
 * @param timeoutSec - Wall-clock limit the parent enforces, in seconds.
 * @returns Text to append to the child's system prompt.
 */
function childSystemPrompt(timeoutSec: number): string {
  return (
    "You are a subagent working in the current directory. Finish assigned task faithfully and report back concisely.\n\n" +
    `This session has a ${timeoutSec}s wall-clock limit; the parent stops it when the limit passes, and anything still pending is abandoned.`
  );
}

/** Longest single JSONL record kept from the child, in bytes. */
const MAX_RECORD_BYTES = 8 * 1024 * 1024;

/** How many finished children are remembered for `subagent_status`. */
const FINISHED_HISTORY = 10;

/** How many of a child's activity steps the status and detail view keep. */
const ACTIVITY_HISTORY = 20;

/** Longest line kept as a text step's tail, the status line's second row. */
const ACTIVITY_TAIL_CHARS = 80;

/**
 * Longest step label kept, in characters.
 *
 * The detail view cuts a row to the terminal width, so a label has to outlast
 * any terminal; this bound only keeps a pathological argument from being held
 * whole. Anything shorter is kept intact.
 */
const ACTIVITY_LABEL_CHARS = 2000;

/** Longest step label the status line quotes, so a poll stays one short line. */
const STATUS_LABEL_CHARS = 60;

/** Characters kept from an open text block, enough to derive its tail line. */
const TEXT_TAIL_BUFFER_CHARS = 400;

/** Kind word of the detail view's pinned spawn line, the moment the child spawned. */
const START_KIND = "start";

/** Schema for the `subagent` tool. */
const SubagentParams = Type.Object({
  prompt: Type.String({
    description:
      "Full task for the subagent. It has no access to this conversation, so include every file path, constraint and deliverable it needs.",
  }),
  id: Type.String({
    description:
      "Short, purpose-bearing name used in every notification, e.g. review-auth or scan-tests.",
  }),
  tools: Type.Optional(
    Type.Array(Type.String(), {
      description:
        'pi tool-selection for the child, passed to --tools: either exact names, e.g. ["read", "bash"], or only +name/-name modifiers on the defaults, e.g. ["+codemode"]. Omit or leave empty for pi defaults.',
    }),
  ),
  model: Type.Optional(
    Type.String({
      description:
        'Model for the child, "provider/id" or a bare id, optionally with a thinking level; `pi --list-models` lists them. Omit to inherit this session\'s model and thinking level.',
    }),
  ),
  cwd: Type.Optional(
    Type.String({
      description:
        "Working directory for the child; defaults to the current one.",
    }),
  ),
  timeoutSec: Type.Optional(
    Type.Number({
      description: `Wall-clock limit for the child, in seconds. The child is stopped and reported as timed out when it passes, which bounds a child that never calls its own finish tool. Defaults to ${DEFAULT_TIMEOUT_SEC}, at most ${MAX_TIMEOUT_SEC}.`,
    }),
  ),
});

/** Ids accepted by `subagent_status` and `subagent_kill`. */
const SelectionParams = Type.Optional(
  Type.Union([Type.String(), Type.Array(Type.String())], {
    description: "One subagent id or a list of ids. Omit for every subagent.",
  }),
);

/** Schema for `subagent_status`. */
const StatusParams = Type.Object({ id: SelectionParams });

/** Schema for `subagent_kill`. */
const KillParams = Type.Object({ id: SelectionParams });

/** Schema for `subagent_finish`, whose answer is the only text the parent sees. */
const FinishParams = Type.Object({
  answer: Type.String({
    description:
      "Your complete final report. This text is the only thing the parent receives, so include all findings; do not refer to earlier messages.",
  }),
});

/** The marker as the model sees it in descriptions, before any id exists. */
const MARKER_EXAMPLE = marker("<id>");

/** A subagent that has not finished yet, as `/subagents` shows it. */
interface RunningSubagent {
  id: string;
  /** Session file the child reported, once `get_state` answered. */
  sessionFile?: string;
  /** Model as requested, empty when the child inherits pi's default. */
  model: string;
  /** Thinking level forced on the child, empty to keep the model's own. */
  thinking: string;
  /** Tools as requested, empty when the child gets pi's defaults. */
  tools: string[];
  cwd: string;
  /** Wall-clock limit the child was given, in seconds of running time. */
  timeoutSec: number;
  /** When the run first started, before any restart, in ms. */
  startedAt: number;
  /** Running time before the current span, in ms: a restart does not count. */
  elapsedMs: number;
  /** When the current running span began, in ms. */
  spanStart: number;
  /** The child's own pi session id, which a resume reopens. */
  childSessionId: string;
  /** Creation order, so two children started in one millisecond stay ordered. */
  order: number;
  /** What the child has been doing, updated from its records. */
  activity: Activity;
}

/** A child that ended, kept briefly so `subagent_status` can report it. */
interface FinishedSubagent {
  id: string;
  /** Session file the child reported, once `get_state` answered. */
  sessionFile?: string;
  /** Elapsed seconds at exit. */
  seconds: number;
  /** Spawn time in ms, shown on the detail's pinned spawn line. */
  startedAt: number;
  /** Outcome word: done, failed, timeout, or killed. */
  state: Exclude<RunState, "running">;
  /** Failure text, when the child did not finish cleanly. */
  reason?: string;
  model: string;
  tools: string[];
  cwd: string;
  /** Wall-clock limit the child was given, in seconds. */
  timeoutSec: number;
  /** Creation order, so two children started in one millisecond stay ordered. */
  order: number;
  /** What it was doing when it ended, for the detail view. */
  activity: Activity;
}

/** One line of the `/subagents` overlay. */
interface SubagentRow {
  id: string;
  /** Session file the child reported, once `get_state` answered. */
  sessionFile?: string;
  /** Outcome word: running, done, failed, timeout, or killed. */
  state: RunState;
  /** Creation order, so two children started in one millisecond stay ordered. */
  order: number;
  /** Elapsed seconds: live while running, at exit once finished. */
  seconds: number;
  model: string;
  tools: string[];
  cwd: string;
  /** Wall-clock limit the child was given, in seconds. */
  timeoutSec: number;
  /** Spawn time in ms, shown on the detail's pinned spawn line. */
  startedAt: number;
  /** What the child has been doing, for the detail view. */
  activity: Activity;
}

/** What the last assistant message of a child says, once its records are parsed. */
interface LastTurn {
  /** Answer text of that message, or an empty string. */
  answer: string;
  /** Terminal stop reason, such as "error", "length" or "aborted". */
  stopReason?: StopReason;
  /** Provider or pi error text, when the turn failed. */
  errorMessage?: string;
  /** Set once a finish call delivered the answer; later records are ignored. */
  final?: boolean;
}

/** One step of a child's activity: a thinking block, text block or tool call. */
interface ActivityStep {
  /** What the child did. */
  kind: "think" | "text" | "tool";
  /** Tool name for a tool step, empty otherwise. */
  tool: string;
  /** First line of a text block, or the argument value naming a tool call. */
  label: string;
  /** Last non-empty line of a text block, for the status line. */
  tail?: string;
  /** Tool call the step belongs to, so its end can find it. */
  callId?: string;
  startedAt: number;
  endedAt?: number;
  /** Characters streamed into a think or text block. */
  chars: number;
}

/**
 * What a child has been doing, updated from its JSONL records.
 *
 * Steps stay bounded and never hold thinking text or a whole text block, so a
 * long run lets the parent see whether the child is busy without the parent's
 * own memory growing with it.
 */
interface Activity {
  /**
   * Lifecycle phase, absent before the child emitted any activity and while a
   * step is open: waiting for the model during a live request, settled once its
   * run is over but the process still holds background work.
   */
  phase?: "waiting" | "settled";
  /** When the current phase began, in ms. */
  phaseStartedAt: number;
  /** The last `ACTIVITY_HISTORY` steps, oldest first. */
  steps: ActivityStep[];
  /**
   * Start of the open text block, `ACTIVITY_LABEL_CHARS` at most.
   *
   * A block that arrives in one large delta never reaches the tail buffer, so
   * the label is read from the head instead of from the step's character count.
   */
  textHead: string;
  /** Characters kept from the open text block, enough to derive its tail. */
  textTail: string;
}

/** One streamed assistant content-block update, as the wire carries it. */
type StreamBlock = Extract<
  JsonAgentSessionEvent,
  { type: "message_update" }
>["assistantMessageEvent"];

/** Terminal state of a child, as its notification reports it. */
interface Outcome {
  state: "done" | "failed" | "timeout";
  /** One-line summary, such as "finished in 12s.". */
  status: string;
  /** What the child said, or why it failed. */
  body: string;
}

/** Plain text of one subagent row, split into aligned columns. */
interface SubagentColumns {
  id: string;
  status: string;
  elapsed: string;
  timeout: string;
  model: string;
  tools: string;
  cwd: string;
}

/** Widest value of each aligned column in one overlay render. */
interface ColumnWidths {
  id: number;
  status: number;
  elapsed: number;
  timeout: number;
  model: number;
  tools: number;
  cwd: number;
}

/**
 * Grace period override, so tests can drive the escalation without waiting.
 * Read on every kill, which keeps a test's value from leaking into others.
 *
 * @returns Milliseconds to wait before sending SIGKILL.
 */
function killGraceMs(): number {
  const override = Number(process.env.SUBAGENT_KILL_GRACE_MS);
  return Number.isFinite(override) && override > 0 ? override : KILL_GRACE_MS;
}

/**
 * Run-start deadline override, so tests need not wait a minute.
 *
 * @returns Milliseconds a child may take to emit `agent_start`.
 */
function startTimeoutMs(): number {
  const override = Number(process.env.SUBAGENT_START_TIMEOUT_MS);
  return Number.isFinite(override) && override > 0
    ? override
    : START_TIMEOUT_MS;
}

/**
 * Format the text that opens every notification about a subagent.
 *
 * The agent keys on this marker to tell a subagent result from its own work,
 * and the tool text names the same form, so promise and delivery cannot drift.
 *
 * @param id - Subagent id, or the `<id>` placeholder in model-facing text.
 * @returns Marker such as `[subagent review-auth]`.
 */
function marker(id: string): string {
  return `[subagent ${id}]`;
}

/**
 * Read the latest assistant text, or a finish call's answer, out of one record.
 *
 * Only completed `message_end` records carry the authoritative answer. A finish
 * call carries the answer the parent is meant to see, so it settles the turn
 * and later records are ignored. Without one, the last assistant message is the
 * fallback for a child that timed out or never called finish.
 *
 * @param lastTurn - Last assistant message, updated in place.
 * @param record - Parsed JSONL record from the child.
 */
function absorbRecord(lastTurn: LastTurn, record: unknown): void {
  if (lastTurn.final) return;

  const event = record as JsonAgentSessionEvent;
  if (event.type !== "message_end" || event.message.role !== "assistant")
    return;

  const message = event.message;
  lastTurn.stopReason = message.stopReason;
  lastTurn.errorMessage = message.errorMessage;
  const finish = message.content.find(
    (part) => part.type === "toolCall" && part.name === FINISH_TOOL,
  );
  const answer =
    finish?.type === "toolCall" ? finish.arguments.answer : undefined;

  if (typeof answer === "string") {
    lastTurn.answer = truncateBytes(answer, OUTPUT_CAP_BYTES);
    lastTurn.final = true;
    return;
  }

  lastTurn.answer = truncateBytes(
    message.content
      .filter(
        (part): part is { type: "text"; text: string } => part.type === "text",
      )
      .map((part) => part.text)
      .join("\n"),
    OUTPUT_CAP_BYTES,
  );
}

/**
 * Fresh activity for a child that has not emitted anything yet.
 *
 * @returns Activity with no phase and no steps.
 */
function emptyActivity(): Activity {
  return { phaseStartedAt: Date.now(), steps: [], textHead: "", textTail: "" };
}

/**
 * Start a new step and append it to the activity, dropping the oldest.
 *
 * @param activity - Activity of the child.
 * @param kind - What the child started doing.
 * @param tool - Tool name for a tool step, empty otherwise.
 * @returns The new step, which later updates happen on in place.
 */
function startStep(
  activity: Activity,
  kind: ActivityStep["kind"],
  tool = "",
): ActivityStep {
  const step: ActivityStep = {
    kind,
    tool,
    label: "",
    startedAt: Date.now(),
    chars: 0,
  };
  activity.steps.push(step);
  if (activity.steps.length > ACTIVITY_HISTORY) activity.steps.shift();
  // An open step is what the child is doing, so it ends the wait. A settled
  // child keeps that phase against late records.
  if (activity.phase === "waiting") activity.phase = undefined;
  return step;
}

/**
 * The most recent step that is still open and matches a predicate.
 *
 * @param activity - Activity of the child.
 * @param match - Which steps qualify.
 * @returns The matching open step, or undefined when there is none.
 */
function openStep(
  activity: Activity,
  match: (step: ActivityStep) => boolean = () => true,
): ActivityStep | undefined {
  for (let i = activity.steps.length - 1; i >= 0; i--) {
    const step = activity.steps[i];
    if (step.endedAt === undefined && match(step)) return step;
  }
  return undefined;
}

/**
 * Close the open step a predicate matches, if there is one.
 *
 * @param activity - Activity of the child.
 * @param match - Which steps qualify.
 */
function closeStep(
  activity: Activity,
  match: (step: ActivityStep) => boolean,
): void {
  const step = openStep(activity, match);
  if (step) step.endedAt = Date.now();
}

/**
 * Report the child as waiting for the model, once it has nothing open.
 *
 * Re-entering the phase keeps its clock, so duplicate lifecycle records do not
 * restart it. A settled child stays settled until a new run begins.
 *
 * @param activity - Activity of the child, updated in place.
 * @param restart - Begin a new wait even if the child had settled.
 */
function waitForModel(activity: Activity, restart = false): void {
  if (openStep(activity)) return;
  if (activity.phase === "waiting") return;
  if (activity.phase === "settled" && !restart) return;
  activity.phase = "waiting";
  activity.phaseStartedAt = Date.now();
}

/**
 * Report the child as settled: its run is over, but its process stays alive
 * for background work. Settled overrides any step that never closed.
 *
 * @param activity - Activity of the child, updated in place.
 */
function settle(activity: Activity): void {
  for (const step of activity.steps) step.endedAt ??= Date.now();
  activity.phase = "settled";
  activity.phaseStartedAt = Date.now();
}

/**
 * Cut text to a character budget, marking an elision.
 *
 * @param text - Text to cut, already a single line.
 * @param maxChars - Character budget, including the marker.
 * @returns The text, or its head followed by "...".
 */
function truncateChars(text: string, maxChars: number): string {
  return text.length > maxChars ? `${text.slice(0, maxChars - 3)}...` : text;
}

/**
 * First or last non-empty line of a text, trimmed and cut short.
 *
 * @param text - Text to scan.
 * @param fromEnd - Take the last non-empty line instead of the first.
 * @param maxChars - Character budget for the line.
 * @returns The line, or an empty string when every line is blank.
 */
function edgeLine(text: string, fromEnd: boolean, maxChars: number): string {
  const lines = text.split("\n");
  const step = fromEnd ? -1 : 1;
  for (
    let i = fromEnd ? lines.length - 1 : 0;
    i >= 0 && i < lines.length;
    i += step
  ) {
    const line = lines[i].trim();
    if (line) return truncateChars(line, maxChars);
  }
  return "";
}

/** Argument keys whose value best names what a tool call does, in order. */
const TOOL_SUMMARY_KEYS = ["command", "path", "pattern", "url", "query", "id"];

/**
 * Summarize the arguments of a tool call for a step label.
 *
 * The named keys cover the tools a child usually calls: a command, a file, a
 * search pattern, a URL, a query or an id. Anything else falls back to the
 * first string value, so an unknown tool still says something useful.
 *
 * @param args - Arguments the child passed to the tool.
 * @returns The first line of that value, or an empty string.
 */
function toolSummary(args: unknown): string {
  if (!args || typeof args !== "object") return "";
  const values = args as Record<string, unknown>;
  const named = TOOL_SUMMARY_KEYS.map((key) => values[key]);
  const value =
    named.find((entry) => typeof entry === "string" && entry !== "") ??
    Object.values(values).find(
      (entry) => typeof entry === "string" && entry !== "",
    );
  return typeof value === "string"
    ? edgeLine(value, false, ACTIVITY_LABEL_CHARS)
    : "";
}

/**
 * Read what a child is doing out of one record.
 *
 * Only lifecycle records move the child between phases, so a bare response or
 * UI record changes nothing. Streaming deltas update the open step in place,
 * so one block or tool call stays one entry.
 *
 * @param activity - Activity of the child, updated in place.
 * @param record - Parsed JSONL record from the child.
 */
function absorbActivity(activity: Activity, record: unknown): void {
  const event = record as JsonAgentSessionEvent;
  switch (event.type) {
    case "agent_start":
    case "turn_start":
      waitForModel(activity, true);
      return;
    case "agent_settled":
      settle(activity);
      return;
    case "message_start":
      if (event.message.role === "assistant") waitForModel(activity, true);
      return;
    case "message_update":
      absorbBlock(activity, event.assistantMessageEvent);
      return;
    case "tool_execution_start": {
      const step = startStep(activity, "tool", event.toolName);
      step.callId = event.toolCallId;
      step.label = toolSummary(event.args);
      return;
    }
    case "tool_execution_end":
      closeStep(activity, (step) => step.callId === event.toolCallId);
      waitForModel(activity);
      return;
    case "message_end":
      // An aborted or failed stream ends its message without closing its
      // blocks; nothing streams into them after this.
      if (event.message.role !== "assistant") return;
      for (const step of activity.steps) {
        if (step.kind !== "tool") step.endedAt ??= Date.now();
      }
      waitForModel(activity);
      return;
  }
}

/**
 * Apply one streamed content-block update to the activity.
 *
 * A delta with no matching open step starts one, so a missing start event
 * costs a label rather than the whole block. Thinking text is counted, never
 * kept; a text block keeps its first line as a label, read from a bounded head
 * buffer, and the last line from a bounded rolling tail buffer. Tool-call
 * arguments stream while the reply is still being prepared, so they open no
 * step of their own.
 *
 * @param activity - Activity of the child, updated in place.
 * @param block - Streamed assistant content-block update.
 */
function absorbBlock(activity: Activity, block: StreamBlock): void {
  switch (block.type) {
    case "thinking_start":
      startStep(activity, "think");
      return;
    case "thinking_delta": {
      const step =
        openStep(activity, (entry) => entry.kind === "think") ??
        startStep(activity, "think");
      step.chars += block.delta.length;
      return;
    }
    case "thinking_end":
      closeStep(activity, (step) => step.kind === "think");
      waitForModel(activity);
      return;
    case "text_start":
      activity.textHead = "";
      activity.textTail = "";
      startStep(activity, "text");
      return;
    case "text_delta": {
      let step = openStep(activity, (entry) => entry.kind === "text");
      if (!step) {
        activity.textHead = "";
        activity.textTail = "";
        step = startStep(activity, "text");
      }
      activity.textHead = (activity.textHead + block.delta).slice(
        0,
        ACTIVITY_LABEL_CHARS,
      );
      activity.textTail = (activity.textTail + block.delta).slice(
        -TEXT_TAIL_BUFFER_CHARS,
      );
      step.chars += block.delta.length;
      // The first line grows over several deltas, so follow it for as long as
      // the head buffer still holds the block's start.
      step.label = edgeLine(activity.textHead, false, ACTIVITY_LABEL_CHARS);
      step.tail = edgeLine(activity.textTail, true, ACTIVITY_TAIL_CHARS);
      return;
    }
    case "text_end":
      closeStep(activity, (step) => step.kind === "text");
      waitForModel(activity);
      return;
  }
}

/**
 * Character count in the compact form the status line uses.
 *
 * @param chars - Characters streamed into a block.
 * @returns Text such as "850 chars" or "1.8k chars".
 */
function charCount(chars: number): string {
  if (chars < 1000) return `${chars} chars`;
  return `${(chars / 1000).toFixed(1)}k chars`;
}

/**
 * What a running child is doing right now, for the status line.
 *
 * @param activity - Activity of the child.
 * @returns Text such as "thinking for 3s (1.8k chars)", "waiting for the
 *   model (12s)" or "idle, waiting on background work (5s)".
 */
function activityNow(activity: Activity): string {
  if (activity.phase === "settled") {
    return `idle, waiting on background work (${elapsedSec(activity.phaseStartedAt)}s)`;
  }
  const step = openStep(activity);
  if (!step) {
    return `waiting for the model (${elapsedSec(activity.phaseStartedAt)}s)`;
  }
  if (step.kind === "think") {
    return `thinking for ${elapsedSec(step.startedAt)}s (${charCount(step.chars)})`;
  }
  if (step.kind === "text") {
    return `writing for ${elapsedSec(step.startedAt)}s (${charCount(step.chars)})`;
  }
  const seconds = elapsedSec(step.startedAt);
  // Only this line stays compact; the detail view shows the whole label.
  return step.label
    ? `${step.tool} \`${truncateChars(step.label, STATUS_LABEL_CHARS)}\` (${seconds}s)`
    : `${step.tool} (${seconds}s)`;
}

/**
 * Second status line of a child that is writing text, when it has one.
 *
 * @param activity - Activity of the child.
 * @returns The open text block's last line, or undefined.
 */
function activityTail(activity: Activity): string | undefined {
  const step = openStep(activity);
  return step?.kind === "text" ? step.tail : undefined;
}

/**
 * Status line of a running child: elapsed time, what it is doing now and for
 * how long.
 *
 * A child that has emitted no activity yet keeps the plain elapsed line: there
 * is nothing to report about it.
 *
 * @param job - Running child.
 * @returns One status line, with a second line for an open text block's tail.
 */
function runningLine(job: RunningSubagent): string {
  const head = `${marker(job.id)} running for ${Math.round(runningMs(job) / 1000)}s`;
  if (job.activity.phase === undefined && job.activity.steps.length === 0)
    return `${head} (${subagentSettings(job)})`;
  const line = `${head}, ${activityNow(job.activity)} (${subagentSettings(job)})`;
  const tail = activityTail(job.activity);
  return tail ? `${line}\n  "...${tail}"` : line;
}

/**
 * Split child output into JSONL records and feed them to `onRecord`.
 *
 * Records are consumed as they arrive, so a long run retains only the latest
 * answer. An oversized record is skipped up to its next newline instead of
 * growing the buffer without bound.
 *
 * @param write - Sink for parser complaints, usually stderr accumulation.
 * @param onRecord - Receiver of each parsed record.
 * @returns A function that accepts output chunks.
 */
function recordParser(
  write: (text: string) => void,
  onRecord: (record: unknown) => void,
) {
  let partial = "";
  let skipping = false;
  const absorb = (line: string) => {
    if (!line.trim()) return;
    try {
      onRecord(JSON.parse(line));
    } catch {
      // A malformed record carries no result; skip it. A lost result is caught
      // by the missing answer at exit, not by this line.
    }
  };
  return (chunk: string) => {
    const lines = (partial + chunk).split("\n");
    partial = lines.pop() ?? "";
    if (skipping) {
      // Only the head of this buffer continues the oversized record; the rest
      // are complete records that still have to be read.
      skipping = false;
      lines.shift();
    }
    // An oversized record has no newline yet, so it cannot carry a result: drop
    // it and keep whatever follows rather than the whole buffer.
    if (Buffer.byteLength(partial, "utf8") > MAX_RECORD_BYTES) {
      partial = "";
      skipping = true;
      write(`subagent: dropped a record over ${MAX_RECORD_BYTES} bytes\n`);
    }
    for (const line of lines) absorb(line);
  };
}

/**
 * Cut a string to at most `maxBytes` UTF-8 bytes, appending a marker.
 *
 * A partial trailing code point is dropped, so the marker stays readable.
 *
 * @param text - Text to trim.
 * @param maxBytes - Byte budget, which the marker may exceed by a few bytes.
 * @returns Text no longer than the budget, plus the marker when cut.
 */
function truncateBytes(text: string, maxBytes: number): string {
  const bytes = Buffer.from(text, "utf8");
  if (bytes.length <= maxBytes) return text;
  const head = new TextDecoder("utf-8").decode(bytes.subarray(0, maxBytes), {
    stream: true,
  });
  return `${head}\n[truncated]`;
}

/**
 * Stop a child process, escalating from SIGTERM to SIGKILL.
 *
 * `proc.killed` only records that a signal was sent, so the real exit state and
 * the `close` event decide when this resolves.
 *
 * @param proc - Process to stop.
 * @returns Whether the process was seen to close, as opposed to surviving the
 *   escalation until the give-up deadline.
 */
function stopProcess(proc: ChildProcess): Promise<boolean> {
  return new Promise((resolve) => {
    if (proc.exitCode !== null || proc.signalCode !== null)
      return resolve(true);
    let closed = false;
    const settle = () => {
      clearTimeout(escalate);
      clearTimeout(giveUp);
      resolve(closed);
    };
    const grace = killGraceMs();
    const escalate = setTimeout(() => proc.kill("SIGKILL"), grace);
    // A process that survives SIGKILL, or a handler that never fires, must not
    // keep the session alive on its own. The caller then knows closure was not
    // observed, which a pause must respect.
    const giveUp = setTimeout(settle, grace * 2);
    proc.once("close", () => {
      closed = true;
      settle();
    });
    proc.kill("SIGTERM");
  });
}

/**
 * Summarize a finished child for its notification.
 *
 * @param lastTurn - Last assistant message of the child.
 * @param stderr - Child stderr, already capped.
 * @param failure - Why the child failed, or undefined for a successful run.
 * @param seconds - Running time of the child, in seconds, for the summary.
 * @param timedOut - Whether the child ran out of wall-clock time, which is
 *   reported as its own outcome so `/subagents` names the cause at a glance.
 * @returns Terminal state, one-line summary and body of the notification.
 */
function outcomeOf(
  lastTurn: LastTurn,
  stderr: string,
  failure: string | undefined,
  seconds: number,
  timedOut: boolean,
): Outcome {
  if (!failure && lastTurn.answer.trim()) {
    return {
      state: "done",
      status: `finished in ${seconds}s.`,
      body: lastTurn.answer,
    };
  }
  // No answer and no reported failure would otherwise read as success, which is
  // how a lost result turns into an invisible one.
  const reason = failure ?? "the child exited without an answer";
  const body = [lastTurn.answer, stderr.trim()].filter(Boolean).join("\n\n");
  const state = timedOut ? "timeout" : "failed";
  return {
    state,
    status: `${state} after ${seconds}s: ${reason}`,
    body: body || "(no output)",
  };
}

/**
 * Seconds since a timestamp, for messages like "finished in 12s.".
 *
 * @param startedAt - Start time in ms.
 * @returns Whole seconds elapsed, at least zero.
 */
function elapsedSec(startedAt: number): number {
  return Math.max(0, Math.round((Date.now() - startedAt) / 1000));
}

/**
 * Seconds of a limit a child may count from its own start.
 *
 * Running time from before that start is taken off, so a resumed child hears
 * what is really left. One decimal keeps a sub-second limit usable without
 * printing a long fraction.
 *
 * @param timeoutSec - Total running-time limit of the run.
 * @param elapsedMs - Running time the run had spent before the child started.
 * @returns Seconds the child may count from its start, never negative.
 */
function childBudget(timeoutSec: number, elapsedMs: number): number {
  return Number(Math.max(0, timeoutSec - elapsedMs / 1000).toFixed(1));
}

/**
 * Running milliseconds of a live run, excluding every pause it survived.
 *
 * @param job - Run whose running time is wanted.
 * @returns Accumulated running time in ms, at least zero.
 */
function runningMs(job: { elapsedMs: number; spanStart: number }): number {
  return job.elapsedMs + Math.max(0, Date.now() - job.spanStart);
}

/**
 * Classify how a child ended, from pi's JSON-mode records.
 *
 * JSON mode exits zero even when the assistant turn failed, so the terminal
 * stop reasons have to be honored here; `aborted` is not a failure because
 * shutdown kills children deliberately.
 *
 * @param lastTurn - Last assistant message, updated in place.
 * @param code - Exit code, or null when the child died from a signal.
 * @param signal - Terminating signal, when any.
 * @returns A failure description, or undefined for a successful run.
 */
function failureOf(
  lastTurn: LastTurn,
  code: number | null,
  signal: NodeJS.Signals | null,
): string | undefined {
  if (code !== 0) {
    return code === null ? `signal ${signal}` : `exit code ${code}`;
  }
  const { stopReason, errorMessage } = lastTurn;
  if (stopReason === "aborted") return "the child aborted the run";
  if (stopReason === "error" || stopReason === "length") {
    return errorMessage || `the child stopped: ${stopReason}`;
  }
  return undefined;
}

/**
 * Tool selection for a child, with the finish tool kept reachable.
 *
 * A selection of plain names is an allowlist, which would otherwise hide the
 * one tool a child needs when background work keeps its session open. A
 * selection made only of `+name`/`-name` modifiers edits the default set
 * instead, and that set already contains every extension tool.
 *
 * @param tools - Selection the caller asked for, possibly empty.
 * @returns The selection to pass to `--tools`.
 */
function childTools(tools: string[]): string[] {
  if (tools.length === 0) return tools;
  const modifiersOnly = tools.every(
    (tool) => tool.startsWith("+") || tool.startsWith("-"),
  );
  if (modifiersOnly) {
    // Only an explicit removal has to be undone; the tool is in the defaults.
    if (!tools.includes(`-${FINISH_TOOL}`)) return tools;
    return [
      ...tools.filter((tool) => tool !== `-${FINISH_TOOL}`),
      `+${FINISH_TOOL}`,
    ];
  }
  if (tools.includes(FINISH_TOOL)) return tools;
  return [...tools, FINISH_TOOL];
}

/**
 * Environment that lets a child reach this session through whatever it loads.
 *
 * Only facts about this session travel here: its intercom id, which survives a
 * `/name` rename, the name to show, and which run the child belongs to. No tool
 * name and no prompt text is involved, so nothing breaks or misleads a child in
 * an environment that has no extension reading these variables; whether a
 * child ends up with a tool that uses them is that extension's business.
 *
 * @param pi - Extension API of this session, read for its display name.
 * @param id - Subagent id: one call is one run of one agent.
 * @param index - Creation order, so a parent can tell siblings apart.
 * @returns Env to add, or undefined when this session is not on intercom.
 */
function bridgeEnv(
  pi: ExtensionAPI,
  id: string,
  index: number,
): Record<string, string> | undefined {
  // Only a session that loaded pi-intercom publishes an id, at its own start.
  // Without one there is nobody for a child to reach, and a bridge missing its
  // required half would be ignored anyway.
  const sessionId = process.env[INTERCOM_SESSION_ID_ENV]?.trim();
  if (!sessionId) return undefined;
  return {
    [ORCHESTRATOR_TARGET_ENV]: pi.getSessionName()?.trim() || sessionId,
    [ORCHESTRATOR_SESSION_ID_ENV]: sessionId,
    [CHILD_RUN_ID_ENV]: id,
    [CHILD_AGENT_ENV]: id,
    [CHILD_INDEX_ENV]: String(index),
    [CHILD_INTERCOM_NAME_ENV]: id,
  };
}

/**
 * Environment for a child pi process.
 *
 * The marker and the deadline are this extension's own contract with its child.
 * Everything that describes this process's own coordination is dropped first,
 * and a bridge is added only when this session has one: a child asks the
 * session that spawned it, and a stale target would point it at the wrong one.
 *
 * @param timeoutSec - Deadline the parent enforces, which the child mirrors.
 * @param bridge - Bridge from `bridgeEnv`, or undefined for none.
 * @returns Environment to spawn the child with.
 */
function childEnv(
  timeoutSec: number,
  bridge: Record<string, string> | undefined,
): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    [CHILD_ENV]: "1",
    [TIMEOUT_ENV]: String(timeoutSec),
  };
  for (const name of NOT_INHERITED_ENV) delete env[name];
  return Object.assign(env, bridge);
}

/**
 * Build the invocation for the child pi process.
 *
 * The child runs in RPC mode: its prompt travels on stdin, and the process stays
 * alive between turns so async tools can wake it. Nothing is passed as a
 * positional argument, because RPC mode rejects `@file` prompts and expects
 * commands on stdin instead.
 *
 * The call's id also names the child's session. Pi's session name is one field
 * that `/name`, `--name` and `pi.setSessionName()` all write, so naming the
 * child here makes every reader of it agree: notifications and `status` say
 * `<id>`, and pi-intercom publishes `<id>` as the child's address instead of
 * the `subagent-chat-<session id>` fallback an unnamed session gets. Without
 * this, a parent can only tell its children apart by model, directory or
 * context size, and none of that survives two children that share them.
 *
 * The child's own `--session-dir` outranks one inherited from this session.
 *
 * A resumed child reopens the session it already has, so its transcript and
 * everything it did before the restart come back with it.
 *
 * @param subagent - Id, model, thinking level, tools and remaining budget.
 * @param childSessionId - The child's own session id, for a fresh or resumed run.
 * @param resuming - Whether that session already exists.
 * @returns Command and arguments to spawn.
 */
function childCommand(
  subagent: {
    id: string;
    model: string;
    thinking: string;
    tools: string[];
    timeoutSec: number;
  },
  childSessionId: string,
  resuming: boolean,
): { command: string; args: string[] } {
  // `pi` on PATH, on purpose: the child need not be the build running here
  // because a bun-compiled pi puts its embedded entry, `/$bunfs/root/pi`, in
  // `argv[1]`, which exists only inside bun's runtime, so `posix_spawn` failed
  // with ENOENT
  const command = process.env.PI_BIN ?? "pi";
  const args = [
    "--mode",
    "rpc",
    "--session-dir",
    path.join(getAgentDir(), SUBAGENT_SESSION_DIR),
    // `--session-id` cannot be combined with `--session`, so the two are
    // alternatives: one names a new session, the other reopens an old one.
    resuming ? "--session" : "--session-id",
    childSessionId,
    "--name",
    subagent.id,
  ];
  if (subagent.model) args.push("--model", subagent.model);
  // Only set on the inherited path: `--thinking` outranks a `:level` suffix.
  if (subagent.thinking) args.push("--thinking", subagent.thinking);
  if (subagent.tools.length > 0) {
    args.push("--tools", childTools(subagent.tools).join(","));
  }
  args.push("--append-system-prompt", childSystemPrompt(subagent.timeoutSec));
  return { command, args };
}

/**
 * Frame a JSONL record for the child's stdin.
 *
 * @param record - Value to serialize.
 * @returns One complete record line.
 */
function jsonLine(record: Record<string, unknown>): string {
  return `${JSON.stringify(record)}\n`;
}

/**
 * Build the `prompt` command that continues a child after a restart.
 *
 * It is not a `Task:` prompt: the child's own session already holds the task,
 * and a new task would send it back to the beginning.
 *
 * @returns One JSONL record for the child's stdin.
 */
function resumeCommand(): string {
  return jsonLine({ id: PROMPT_ID, type: "prompt", message: RESUME_MESSAGE });
}

/**
 * Build the `prompt` command that starts the child's run.
 *
 * The `Task:` prefix keeps pi from reading the prompt as a skill, template or
 * extension command, which RPC mode would dispatch instead of sending it.
 * Nothing else is added: how long the child may run lives in its system prompt,
 * where the parent already states it once.
 *
 * @param prompt - Task the caller described.
 * @returns One JSONL record for the child's stdin.
 */
function promptCommand(prompt: string): string {
  return jsonLine({
    id: PROMPT_ID,
    type: "prompt",
    message: `Task: ${prompt}`,
  });
}

/**
 * Ask the child where it keeps its transcript.
 *
 * The child names its own session file, so the parent has to be told; the
 * answer arrives as a `response` record like any other command.
 *
 * @returns One JSONL record for the child's stdin.
 */
function stateCommand(): string {
  return jsonLine({ id: STATE_ID, type: "get_state" });
}

/**
 * Answer a child's extension UI record, which no user can see.
 *
 * Fire-and-forget records such as `notify` need no answer and pi ignores a
 * response to them, so every request is cancelled instead of only the dialog
 * methods of the day: a future blocking method must not park the child forever.
 *
 * @param record - Parsed child record.
 * @returns The response record, or undefined when this is not a UI request.
 */
function uiCancellation(record: unknown): string | undefined {
  const request = record as { type?: unknown; id?: unknown };
  if (request.type !== "extension_ui_request") return undefined;
  if (typeof request.id !== "string") return undefined;
  return jsonLine({
    type: "extension_ui_response",
    id: request.id,
    cancelled: true,
  });
}

/**
 * Read a prompt the child will not run.
 *
 * A refused prompt starts no run, and neither does one an extension consumed,
 * so without this the call would wait for a child that can never finish.
 *
 * @param record - Parsed child record.
 * @returns Why no run will happen, or undefined for any other record.
 */
function promptRejection(record: unknown): string | undefined {
  const response = record as {
    id?: unknown;
    type?: unknown;
    command?: unknown;
    success?: unknown;
    error?: unknown;
    data?: { disposition?: unknown };
  };
  if (
    response.type !== "response" ||
    response.command !== "prompt" ||
    response.id !== PROMPT_ID
  )
    return undefined;
  if (response.success === false) {
    return typeof response.error === "string" && response.error !== ""
      ? response.error
      : "the child rejected its prompt";
  }
  // `handled` means an extension command or input handler consumed the prompt
  // and no run started, so no settle would ever end the child.
  if (response.data?.disposition === "handled") {
    return "the child handed its prompt to an extension instead of running";
  }
  return undefined;
}

/**
 * Stop a child that a dead parent left behind.
 *
 * A record still marked running only exists because its pi died hard, so the
 * child may still be working with nobody to stop it at its deadline. Its own
 * command line carries this extension's mode, name and session id, which is
 * enough to identify that exact process: an interactive pi a user opened to
 * inspect the child has none of them.
 *
 * @param run - Record the dead parent left behind.
 */
function reapOrphan(run: RunRecord): void {
  const listing = spawnSync("ps", ["-Ao", "pid=,command="], {
    encoding: "utf8",
  });
  if (listing.status !== 0) return;
  for (const line of listing.stdout.split("\n")) {
    const match = /^\s*(\d+)\s+(.*)$/.exec(line);
    if (!match) continue;
    const [, pid, command] = match;
    const named =
      command.includes(`--session-id ${run.childSessionId}`) ||
      command.includes(`--session ${run.childSessionId}`);
    if (!named) continue;
    if (!command.includes("--mode rpc")) continue;
    if (!command.includes(`--name ${run.id}`)) continue;
    try {
      process.kill(Number(pid), "SIGTERM");
    } catch {
      // It exited between the listing and the signal; nothing to reap.
    }
  }
}

/**
 * The last record of every run a session branch holds.
 *
 * A run appends one record per lifecycle step, so only the newest one states
 * what the run is doing now. Map order is first insertion, which is the order
 * the runs started in.
 *
 * @param entries - Session branch entries, oldest first.
 * @returns The newest record of each run id.
 */
function lastRunRecords(
  entries: readonly SessionEntry[],
): Map<string, RunRecord> {
  const runs = new Map<string, RunRecord>();
  for (const entry of entries) {
    if (entry.type !== "custom" || entry.customType !== RUN_ENTRY) continue;
    const record = entry.data as RunRecord | undefined;
    if (record?.id) runs.set(record.id, record);
  }
  return runs;
}

/**
 * Read the state a child reported in its answer to `get_state`.
 *
 * A child that keeps no session file reports none, so that stays undefined
 * instead of inventing a path.
 *
 * @param record - Parsed child record.
 * @returns The child's session file and id, when this record answers the query.
 */
function childState(record: unknown): {
  sessionFile?: string;
  sessionId?: string;
} {
  const response = record as {
    id?: unknown;
    type?: unknown;
    command?: unknown;
    data?: { sessionFile?: unknown; sessionId?: unknown };
  };
  if (
    response.type !== "response" ||
    response.command !== "get_state" ||
    response.id !== STATE_ID
  )
    return {};
  const { sessionFile, sessionId } = response.data ?? {};
  return {
    sessionFile:
      typeof sessionFile === "string" && sessionFile !== ""
        ? sessionFile
        : undefined,
    sessionId:
      typeof sessionId === "string" && sessionId !== "" ? sessionId : undefined,
  };
}

/**
 * Whether a record marks the start of the child's first run.
 *
 * @param record - Parsed child record.
 * @returns True for an `agent_start` event.
 */
function isAgentStart(record: unknown): boolean {
  return (record as { type?: unknown }).type === "agent_start";
}

/**
 * Read an extension failure the child reported.
 *
 * @param record - Parsed child record.
 * @returns A one-line description, or undefined for any other record.
 */
function extensionError(record: unknown): string | undefined {
  const failure = record as {
    type?: unknown;
    extensionPath?: unknown;
    event?: unknown;
    error?: unknown;
  };
  if (failure.type !== "extension_error") return undefined;
  return `subagent: extension error in ${String(failure.extensionPath)} on ${String(failure.event)}: ${String(failure.error)}`;
}

/**
 * Write one JSONL record to the child's stdin.
 *
 * A child that already exited leaves its pipe closed; that is reported into the
 * failure text instead of throwing out of the child's stdout handler.
 *
 * @param proc - Child process.
 * @param line - Complete record line.
 * @param report - Sink for write complaints.
 */
function writeChild(
  proc: ChildProcess,
  line: string,
  report: (text: string) => void,
): void {
  const stdin = proc.stdin;
  if (!stdin || stdin.destroyed || !stdin.writable) {
    report("subagent: the child's stdin is closed\n");
    return;
  }
  stdin.write(line, (error) => {
    if (error)
      report(`subagent: cannot write to the child: ${error.message}\n`);
  });
}

/**
 * Choose the model and thinking level for a child.
 *
 * An explicit `model` wins and carries its own optional `:thinking` suffix.
 * Otherwise the child inherits this session's selection. Pi does not do that on
 * its own: a child started without `--model` resolves the configured default,
 * so after a mid-session model switch a bare child would silently run another
 * model than its parent.
 *
 * @param model - Model the caller asked for, or an empty string.
 * @param ctx - Tool context holding the session's model and thinking level.
 * @returns The `--model` value, and the thinking level to force instead.
 */
function childSelection(
  model: string,
  ctx: Pick<ExtensionContext, "model" | "thinkingLevel">,
): { model: string; thinking: string } {
  if (model || !ctx.model) return { model, thinking: "" };
  return {
    model: `${ctx.model.provider}/${ctx.model.id}`,
    thinking: ctx.thinkingLevel ?? "",
  };
}

/**
 * Model column text.
 *
 * @param job - Model of the child.
 * @returns The model, or the inherited-model fallback.
 */
function modelLabel(job: { model: string }): string {
  return job.model || "model=default";
}

/**
 * Tools column text.
 *
 * @param job - Tools of the child.
 * @returns The tool list, or the inherited-tools fallback.
 */
function toolsLabel(job: { tools: string[] }): string {
  return job.tools.length > 0
    ? `tools=${job.tools.join(",")}`
    : "tools=default";
}

/**
 * Describe a child's model, tools, working directory and timeout on one line.
 *
 * @param job - Model, tools, working directory and timeout of the child.
 * @returns Text such as "qoder/Fast, tools=read,bash, /work, timeout=600s".
 */
function subagentSettings(job: {
  model: string;
  tools: string[];
  cwd: string;
  timeoutSec: number;
}): string {
  return [
    modelLabel(job),
    toolsLabel(job),
    job.cwd,
    timeoutLabel(job.timeoutSec),
  ].join(", ");
}

/**
 * Split a row into the plain text of each column.
 *
 * @param row - Subagent to split.
 * @returns The column values, without colors or padding.
 */
function columnsOf(row: SubagentRow): SubagentColumns {
  return {
    id: row.id,
    status: row.state,
    elapsed: `${row.seconds}s`,
    timeout: timeoutLabel(row.timeoutSec),
    model: modelLabel(row),
    tools: toolsLabel(row),
    cwd: row.cwd,
  };
}

/**
 * Deadline column text.
 *
 * @param seconds - Wall-clock limit the child was given.
 * @returns Text such as "timeout=600s".
 */
function timeoutLabel(seconds: number): string {
  return `timeout=${seconds}s`;
}

/**
 * Measure the widest value of every column, so rows can line up.
 *
 * @param rows - Rows the overlay shows.
 * @returns The terminal width of each column.
 */
function alignWidths(rows: readonly SubagentRow[]): ColumnWidths {
  const keys = [
    "id",
    "status",
    "elapsed",
    "timeout",
    "model",
    "tools",
    "cwd",
  ] as const;
  const widths: ColumnWidths = {
    id: 0,
    status: 0,
    elapsed: 0,
    timeout: 0,
    model: 0,
    tools: 0,
    cwd: 0,
  };
  for (const row of rows) {
    const column = columnsOf(row);
    for (const key of keys) {
      widths[key] = Math.max(widths[key], visibleWidth(column[key]));
    }
  }
  return widths;
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
 * Detail-view kind column of a step.
 *
 * @param step - Step to describe.
 * @returns "think", "text", or the tool name.
 */
function stepKind(step: ActivityStep): string {
  return step.kind === "tool" ? step.tool : step.kind;
}

/**
 * Detail-view suffix of a step that is still open.
 *
 * @param step - Step to describe.
 * @returns Text such as "running 35s" or "writing", empty once it closed.
 */
function openSuffix(step: ActivityStep): string {
  if (step.endedAt !== undefined) return "";
  if (step.kind === "tool") return `running ${elapsedSec(step.startedAt)}s`;
  return step.kind === "text" ? "writing" : "thinking";
}

/**
 * Settings line of one child's detail view.
 *
 * @param row - Child the view shows.
 * @param stateMarker - Styled state marker of the child.
 * @param theme - Active theme.
 * @returns Text naming its id, state marker, state, elapsed time, timeout,
 *   model, tools and working directory, in the order the list row shows them.
 */
function detailHeader(
  row: SubagentRow,
  stateMarker: string,
  theme: Theme,
): string {
  const column = columnsOf(row);
  const state =
    row.state === "running"
      ? `running for ${row.seconds}s`
      : `${row.state} after ${row.seconds}s`;
  return [
    theme.bold(column.id),
    stateMarker,
    theme.fg("muted", state),
    theme.fg("dim", column.timeout),
    theme.fg("dim", column.model),
    theme.fg("dim", column.tools),
    theme.fg("dim", column.cwd),
  ].join(" ");
}

/**
 * Spawn moment of one child, pinned above the steps of its detail view.
 *
 * @param row - Child the view shows.
 * @param theme - Active theme.
 * @returns Text such as "16:51:36 start".
 */
function startLine(row: SubagentRow, theme: Theme): string {
  return [
    theme.fg("dim", clockTime(row.startedAt)),
    theme.fg("muted", START_KIND),
  ].join(" ");
}

/**
 * Where the child keeps its transcript, under the detail's summary.
 *
 * One row, like the summary line above it: a path that wraps would push the
 * body and the hint out of a short terminal.
 *
 * @param sessionFile - Absolute path the child reported.
 * @param width - Columns the line may fill.
 * @param theme - Active theme.
 * @returns Styled text such as "session /…/2026-01-02T03-04-05-678Z_ab.jsonl".
 */
function sessionLine(sessionFile: string, width: number, theme: Theme): string {
  return theme.fg(
    "dim",
    truncateToWidth(`session ${sessionFile}`, width, "..."),
  );
}

/**
 * Summary line of the `/subagents` overlay.
 *
 * @param rows - Rows the overlay shows.
 * @param theme - Active theme.
 * @returns A styled count, or the empty state.
 */
function summaryOf(rows: SubagentRow[], theme: Theme): string {
  if (rows.length === 0) {
    return theme.fg("dim", "No subagents have run in this session.");
  }
  const running = rows.filter((row) => row.state === "running").length;
  return theme.fg(
    "muted",
    `${running} running, ${rows.length - running} finished`,
  );
}

/**
 * Order two subagents, or two of their rows, by when they were created.
 *
 * `order` is a monotonic counter rather than the spawn time, so two children
 * started in one millisecond still have an order of their own.
 *
 * @param left - Left row or child.
 * @param right - Right row or child.
 * @returns Negative when `left` was created first.
 */
function byCreation(left: { order: number }, right: { order: number }): number {
  return left.order - right.order;
}

/**
 * The session's subagents: who is running, and how their results get back.
 *
 * One instance per extension load. It owns the child processes, so a shutdown
 * that kills them and the notification that would otherwise arrive afterwards
 * cannot disagree about what is still alive.
 */
class SubagentRunner {
  /** Subagents that have not been reported yet, by id. */
  private running = new Map<string, RunningSubagent>();
  /** Live child processes, by id, killed on shutdown. */
  private children = new Map<string, ChildProcess>();
  /** Recently finished children, newest last, so status can answer "did it end?". */
  private finished: FinishedSubagent[] = [];
  /** Per-child stop hooks, so a kill can end one child without touching others. */
  private stoppers = new Map<string, () => Promise<void>>();
  /** Set once the session shuts down: pending notifications are dropped. */
  private shuttingDown = false;
  /** Session manager shared with the other extensions that wake Pi. */
  private session?: WakeSession;
  /** Whether a run is active, i.e. whether a result would start one. */
  private busy = false;
  /**
   * Set when the child's model called `subagent_finish`.
   *
   * Only meaningful in a spawned child, where nothing else ends the session:
   * the model is the one who knows the task is over.
   */
  private finishAsked = false;
  /** Monotonic creation order for the overlay rows. */
  private nextOrder = 1;
  /**
   * Session id that owns the runs this runner started.
   *
   * Set when the session starts and when a tool uses the session, so every
   * record names its owner and a fork can tell another session's runs apart.
   */
  private owner = "";
  /** Overlay the `/subagents` command shows, while it is open. */
  private overlay?: SubagentsOverlay;

  /** Extension API used to inject notifications. */
  private readonly pi: ExtensionAPI;

  constructor(pi: ExtensionAPI) {
    this.pi = pi;
  }

  /**
   * Reserve the call's id, or report why the call is unusable.
   *
   * The id only labels notifications and keeps concurrent children apart, so
   * nothing here restricts its characters.
   *
   * @param id - Id requested by the caller, which must not be blank.
   * @param cwd - Absolute working directory for the child.
   * @returns The id to use, or the problem to report to the agent.
   */
  reserveId(id: string, cwd: string): { id: string } | { problem: string } {
    const requested = id.trim();
    if (requested === "")
      return { problem: "The subagent id must not be empty." };
    if (this.running.has(requested)) {
      return { problem: `A subagent named "${requested}" is already running.` };
    }
    if (!fs.statSync(cwd, { throwIfNoEntry: false })?.isDirectory()) {
      return { problem: `Working directory is not a directory: ${cwd}` };
    }
    return { id: requested };
  }

  /**
   * Start a child, or resume one a previous parent paused.
   *
   * A resumed run keeps the running time it already spent, so its budget and
   * the deadline the child is told are what is left of it, and it reopens the
   * session it was working in.
   *
   * @param subagent - Id, prompt, model, thinking level, tools, working
   *   directory and wall-clock budget of the run.
   * @param resume - Record to continue, or undefined for a fresh run.
   */
  start(subagent: StartRequest, resume?: RunRecord): void {
    const childSessionId = resume?.childSessionId ?? randomUUID();
    const elapsedMs = resume?.elapsedMs ?? 0;
    const startedAt = resume?.startedAt ?? Date.now();
    const order = resume?.order ?? this.nextOrder++;
    this.nextOrder = Math.max(this.nextOrder, order + 1);
    const remainingSec = childBudget(subagent.timeoutSec, elapsedMs);
    const bridge = bridgeEnv(this.pi, subagent.id, order);
    const { command, args } = childCommand(
      { ...subagent, timeoutSec: remainingSec },
      childSessionId,
      resume !== undefined,
    );
    const proc = spawn(command, args, {
      cwd: subagent.cwd,
      shell: false,
      stdio: ["pipe", "pipe", "pipe"],
      env: childEnv(remainingSec, bridge),
    });

    this.children.set(subagent.id, proc);
    const running: RunningSubagent = {
      id: subagent.id,
      model: subagent.model,
      thinking: subagent.thinking,
      tools: subagent.tools,
      cwd: subagent.cwd,
      timeoutSec: subagent.timeoutSec,
      startedAt,
      elapsedMs,
      spanStart: Date.now(),
      childSessionId,
      order,
      activity: emptyActivity(),
    };
    this.running.set(running.id, running);
    this.record(running, "running", elapsedMs);
    this.refreshOverlay();

    const lastTurn: LastTurn = { answer: "" };
    let stderrTail = "";
    let startFailure = "";
    let runStarted = false;
    let startDeadline: ReturnType<typeof setTimeout> | undefined;
    let timeout: ReturnType<typeof setTimeout> | undefined;
    let finished = false;
    let stopped = false;

    const appendStderr = (text: string) => {
      stderrTail = truncateBytes(stderrTail + text, STDERR_CAP_BYTES);
    };
    /** The child has begun its run, so the start deadline no longer applies. */
    const runBegan = () => {
      runStarted = true;
      clearTimeout(startDeadline);
    };
    const onRecord = (record: unknown) => {
      absorbRecord(lastTurn, record);
      // A reported or stopped child keeps the activity it ended with, even
      // while its process is still dying.
      if (!finished && !stopped) absorbActivity(running.activity, record);
      if (isAgentStart(record)) runBegan();
      const state = childState(record);
      if (state.sessionFile) {
        running.sessionFile = state.sessionFile;
        this.refreshOverlay();
      }
      // Anything but the session this run named is a different conversation:
      // resuming into it would continue someone else's work.
      if (state.sessionId && state.sessionId !== running.childSessionId) {
        startFailure = `the child opened session ${state.sessionId} instead of ${running.childSessionId}`;
        void stopProcess(proc);
        return;
      }
      const cancellation = uiCancellation(record);
      if (cancellation) {
        writeChild(proc, cancellation, appendStderr);
        return;
      }
      const rejection = promptRejection(record);
      if (rejection) {
        startFailure = rejection;
        void stopProcess(proc);
        return;
      }
      const failure = extensionError(record);
      if (failure) appendStderr(`${failure}\n`);
    };
    // In RPC mode a malformed record is the only place a parser complaint can
    // go; it lands next to the child's own stderr.
    proc.stdout.setEncoding("utf8");
    proc.stdout.on("data", recordParser(appendStderr, onRecord));
    proc.stderr.setEncoding("utf8");
    proc.stderr.on("data", appendStderr);
    proc.stdin?.on("error", (error) =>
      appendStderr(`subagent: stdin error: ${error.message}\n`),
    );

    // `error` and `close` can both fire for one child; report it only once.
    const finish = (failure: string | undefined, timedOut = false) => {
      if (finished) return;
      finished = true;
      clearTimeout(startDeadline);
      clearTimeout(timeout);
      if (this.children.get(running.id) === proc) {
        this.children.delete(running.id);
      }
      if (this.shuttingDown || stopped) return;
      this.stoppers.delete(running.id);
      this.running.delete(running.id);
      const elapsed = runningMs(running);
      const outcome = outcomeOf(
        lastTurn,
        stderrTail,
        failure,
        Math.round(elapsed / 1000),
        timedOut,
      );
      this.record(running, outcome.state, elapsed);
      this.remember({
        id: running.id,
        sessionFile: running.sessionFile,
        seconds: Math.round(elapsed / 1000),
        startedAt: running.startedAt,
        state: outcome.state,
        reason: failure,
        model: running.model,
        tools: running.tools,
        cwd: running.cwd,
        timeoutSec: running.timeoutSec,
        order: running.order,
        activity: running.activity,
      });
      this.refreshOverlay();
      this.deliver(running.id, outcome);
    };

    this.stoppers.set(running.id, () => {
      stopped = true;
      return stopProcess(proc);
    });
    // A child that never calls its own finish tool, or that hangs on an
    // extension error, still has to report instead of living on. The deadline
    // counts running time, so it survives a pause with its budget.
    // Unref'd: this deadline must not keep the parent's event loop alive.
    const armTimeout = () => {
      clearTimeout(timeout);
      const remainingMs = running.timeoutSec * 1000 - runningMs(running);
      timeout = setTimeout(
        () => {
          finish(`no result within its ${running.timeoutSec}s timeout`, true);
          void stopProcess(proc);
        },
        Math.max(0, remainingMs),
      );
      timeout.unref();
    };

    proc.on("error", (error) => finish(`spawn error: ${error.message}`));
    proc.on("close", (code, signal) =>
      finish(startFailure || failureOf(lastTurn, code, signal)),
    );
    // The readers are attached first, so a fast answer cannot arrive unread.
    writeChild(proc, stateCommand(), appendStderr);
    writeChild(
      proc,
      resume ? resumeCommand() : promptCommand(subagent.prompt),
      appendStderr,
    );
    // A child that never starts a run cannot report, and its gate never fires.
    // Unref'd: this deadline must not keep the parent's event loop alive.
    startDeadline = setTimeout(() => {
      if (runStarted || finished) return;
      startFailure = "the child never started a run";
      void stopProcess(proc);
    }, startTimeoutMs());
    startDeadline.unref();
    armTimeout();
  }

  /** Record that the child's model asked to end the session. */
  requestFinish(): void {
    this.finishAsked = true;
  }

  /**
   * Whether the child's model asked to end the session.
   *
   * @returns True once `requestFinish()` was called.
   */
  finishRequested(): boolean {
    return this.finishAsked;
  }

  /**
   * Keep a finished child in the bounded history.
   *
   * @param job - What to remember about it.
   */
  private remember(job: FinishedSubagent): void {
    this.finished.push(job);
    if (this.finished.length > FINISHED_HISTORY) this.finished.shift();
  }

  /**
   * Describe every subagent this session knows about, running ones first.
   *
   * @param only - Ids to report, or omitted for all of them.
   * @returns One line per subagent in creation order within each group, or an
   *   explanation when nothing matched.
   */
  status(only?: string[]): string {
    const wanted = new Set(only ?? []);
    const matches = (id: string) => wanted.size === 0 || wanted.has(id);
    const running = [...this.running.values()]
      .filter((job) => matches(job.id))
      .map((job) => runningLine(job));
    const finished = this.finished
      .filter((job) => matches(job.id))
      .sort(byCreation)
      .map(
        (job) =>
          `${marker(job.id)} ${job.state} after ${job.seconds}s (${timeoutLabel(job.timeoutSec)})${job.reason ? `: ${job.reason}` : ""}`,
      );
    const lines = [...running, ...finished];
    if (lines.length > 0) return lines.join("\n");
    return wanted.size === 0
      ? "No subagents have run in this session."
      : `No subagent named ${[...wanted].map(marker).join(", ")}.`;
  }

  /**
   * Create and track the overlay for the `/subagents` command.
   *
   * The overlay reads live state on every render, so it only needs refreshing
   * as children start, speak and finish.
   *
   * @param tui - TUI the overlay renders into.
   * @param theme - Active theme.
   * @param keybindings - User keybindings the list navigation follows.
   * @param close - Closes the overlay.
   * @returns The overlay component.
   */
  createOverlay(
    tui: TUI,
    theme: Theme,
    keybindings: KeybindingsManager,
    close: () => void,
  ): SubagentsOverlay {
    const overlay = new SubagentsOverlay(
      tui,
      theme,
      keybindings,
      () => this.rows(),
      close,
    );
    this.overlay = overlay;
    this.refreshOverlay();
    return overlay;
  }

  /** Forget the overlay after `/subagents` closed it. */
  detachOverlay(): void {
    this.overlay = undefined;
  }

  /**
   * Describe every subagent this session knows about, running ones first.
   *
   * @returns One row per running child and per remembered finished child, each
   *   group in creation order.
   */
  private rows(): SubagentRow[] {
    const running = [...this.running.values()]
      .map((job) => ({
        id: job.id,
        sessionFile: job.sessionFile,
        state: "running" as const,
        order: job.order,
        seconds: Math.round(runningMs(job) / 1000),
        startedAt: job.startedAt,
        model: job.model,
        tools: job.tools,
        cwd: job.cwd,
        timeoutSec: job.timeoutSec,
        activity: job.activity,
      }))
      .sort(byCreation);
    const finished = this.finished
      .map((job) => ({
        id: job.id,
        sessionFile: job.sessionFile,
        state: job.state,
        order: job.order,
        seconds: job.seconds,
        startedAt: job.startedAt,
        model: job.model,
        tools: job.tools,
        cwd: job.cwd,
        timeoutSec: job.timeoutSec,
        activity: job.activity,
      }))
      .sort(byCreation);
    return [...running, ...finished];
  }

  /** Re-render the overlay after a state change, when it is open. */
  private refreshOverlay(): void {
    this.overlay?.refresh();
  }

  /**
   * Stop subagents and release their ids.
   *
   * @param only - Ids to stop, or omitted for every running child.
   * @returns Ids that were stopped, and ids that were not running.
   */
  async kill(
    only?: string[],
  ): Promise<{ stopped: string[]; unknown: string[] }> {
    const wanted = only && only.length > 0 ? only : [...this.running.keys()];
    const stopped: string[] = [];
    const unknown: string[] = [];
    const waits: Promise<void>[] = [];
    for (const id of wanted) {
      const job = this.running.get(id);
      const stop = this.stoppers.get(id);
      if (!job || !stop) {
        unknown.push(id);
        continue;
      }
      stopped.push(id);
      const elapsed = runningMs(job);
      this.record(job, "killed", elapsed);
      this.remember({
        id,
        sessionFile: job.sessionFile,
        seconds: Math.round(elapsed / 1000),
        startedAt: job.startedAt,
        state: "killed",
        model: job.model,
        tools: job.tools,
        cwd: job.cwd,
        timeoutSec: job.timeoutSec,
        order: job.order,
        activity: job.activity,
      });
      this.running.delete(id);
      this.stoppers.delete(id);
      waits.push(stop());
    }
    await Promise.all(waits);
    this.refreshOverlay();
    return { stopped, unknown };
  }

  /**
   * Pause every child and stop delivering results.
   *
   * A pause is not a loss. Each child's running time and its own session id go
   * into this session, so the next pi that opens the session resumes it with
   * what is left of its budget. `stopProcess` owns the signal escalation, and
   * SIGTERM lets a child run its own shutdown hooks before it exits.
   */
  async shutdown(): Promise<void> {
    this.shuttingDown = true;
    this.overlay?.dispose();
    this.overlay = undefined;
    const jobs = [...this.running.values()];
    this.running.clear();
    await Promise.all(
      jobs.map(async (job) => {
        const proc = this.children.get(job.id);
        const closed = proc ? await stopProcess(proc) : true;
        // Only a child that is gone may be resumed later: a paused record while
        // one could still be alive would let the next parent share its session.
        // The time is measured to the close, so the grace period counts too.
        if (closed) this.record(job, "paused", runningMs(job));
      }),
    );
    this.children.clear();
    this.stoppers.clear();
  }

  /**
   * Resume the runs this session paused before its last shutdown.
   *
   * The branch records every step of a run, so the last record of each id
   * decides. A run that ended stays ended, a paused run continues with the
   * budget it has left, and a run still marked running belonged to a pi process
   * that died without pausing it: its child may still be out there, so resuming
   * it would give one child session file two writers. Only the branch counts, so
   * a branch that predates a run's last record reads as interrupted; such a run
   * is reported, never resumed.
   *
   * @param ctx - Context of the session that is starting.
   * @param reason - Why it started, so a reload can stay quiet for the user too.
   */
  restore(ctx: ExtensionContext, reason: SessionStartEvent["reason"]): void {
    this.attach(ctx.sessionManager);
    const owner = ctx.sessionManager.getSessionId();
    this.owner = owner;
    const resumed: string[] = [];
    for (const run of lastRunRecords(ctx.sessionManager.getBranch()).values()) {
      // A fork copies another session's entries verbatim; only the session that
      // wrote them may run their children, or two parents would share one.
      if (run.owner !== owner) continue;
      if (run.state === "running") {
        this.interrupt(run);
        continue;
      }
      if (run.state !== "paused") continue;
      this.nextOrder = Math.max(this.nextOrder, run.order + 1);
      if (run.timeoutSec * 1000 - run.elapsedMs <= 0) {
        this.exhaust(run);
        continue;
      }
      this.start(
        {
          id: run.id,
          // A resumed child continues its own session; the task it was given
          // is part of that session already.
          prompt: "",
          model: run.model,
          thinking: run.thinking,
          tools: run.tools,
          cwd: run.cwd,
          timeoutSec: run.timeoutSec,
        },
        run,
      );
      resumed.push(run.id);
    }
    if (resumed.length > 0 && reason !== "reload") {
      ctx.ui.notify(
        `Resumed ${resumed.length} subagent(s) after a restart: ${resumed.map(marker).join(", ")}.`,
      );
    }
  }

  /**
   * Remember the session the wake contract is shared on.
   *
   * Called from `restore()`, which every session runs before a tool can, so a
   * result delivered later always has a session to check.
   *
   * @param session - Session manager of the calling context.
   */
  attach(session: WakeSession): void {
    this.session = session;
  }

  /**
   * Track whether a run is active.
   *
   * A result only starts a run for an idle session; during a run pi queues it,
   * so the result must neither wait for a reservation nor hold one that would
   * keep another extension from waking an idle session later.
   *
   * @param busy - True between `agent_start` and `agent_settled`.
   */
  setBusy(busy: boolean): void {
    this.busy = busy;
  }

  /**
   * Name the session that owns the runs started from here.
   *
   * @param owner - Session id pi has bound.
   */
  claim(owner: string): void {
    this.owner = owner;
  }

  /**
   * Append one step of a run's lifecycle to the session.
   *
   * @param job - Run to record.
   * @param state - Lifecycle state this step states.
   * @param elapsedMs - Running time spent so far, in ms.
   */
  private record(
    job: RunningSubagent,
    state: RunRecordState,
    elapsedMs: number,
  ): void {
    this.pi.appendEntry(RUN_ENTRY, {
      id: job.id,
      state,
      model: job.model,
      thinking: job.thinking,
      tools: job.tools,
      cwd: job.cwd,
      timeoutSec: job.timeoutSec,
      elapsedMs,
      startedAt: job.startedAt,
      order: job.order,
      childSessionId: job.childSessionId,
      owner: this.owner,
    } satisfies RunRecord);
  }

  /**
   * Report a run whose parent died without pausing it.
   *
   * @param run - Last record the dead parent left behind.
   */
  private interrupt(run: RunRecord): void {
    reapOrphan(run);
    const reason = "interrupted when pi died";
    this.pi.appendEntry(RUN_ENTRY, {
      ...run,
      state: "failed",
    } satisfies RunRecord);
    this.remember({
      id: run.id,
      seconds: Math.round(run.elapsedMs / 1000),
      startedAt: run.startedAt,
      state: "failed",
      reason,
      model: run.model,
      tools: run.tools,
      cwd: run.cwd,
      timeoutSec: run.timeoutSec,
      order: run.order,
      activity: emptyActivity(),
    });
    // Not a wake: a session that opens with stale news should not spend a model
    // turn before its user says anything. The notice waits for the next one.
    this.deliver(
      run.id,
      {
        state: "failed",
        status: `failed after ${Math.round(run.elapsedMs / 1000)}s: ${reason}`,
        body: "(no output)",
      },
      false,
    );
  }

  /**
   * Report a paused run that has no budget left to resume with.
   *
   * @param run - Last record the paused run left behind.
   */
  private exhaust(run: RunRecord): void {
    const reason = `no result within its ${run.timeoutSec}s timeout`;
    this.pi.appendEntry(RUN_ENTRY, {
      ...run,
      state: "timeout",
    } satisfies RunRecord);
    this.remember({
      id: run.id,
      seconds: Math.round(run.elapsedMs / 1000),
      startedAt: run.startedAt,
      state: "timeout",
      reason,
      model: run.model,
      tools: run.tools,
      cwd: run.cwd,
      timeoutSec: run.timeoutSec,
      order: run.order,
      activity: emptyActivity(),
    });
    // Same as a crash report: visible at once, no turn spent on it.
    this.deliver(
      run.id,
      {
        state: "timeout",
        status: `timeout after ${Math.round(run.elapsedMs / 1000)}s: ${reason}`,
        body: "(no output)",
      },
      false,
    );
  }

  /**
   * Queue the result at pi's next safe turn boundary, or wake an idle parent.
   *
   * Steering does not interrupt an in-flight request or tool execution. Pi
   * owns message ordering and continuation, so no idle polling is needed.
   *
   * @param id - Id of the run whose result this is.
   * @param outcome - What the run ended with.
   * @param wake - Whether an idle parent should start a turn for it.
   */
  private deliver(id: string, outcome: Outcome, wake = true): void {
    const message = {
      customType: NOTICE_TYPE,
      content: `${marker(id)} ${outcome.status}\n\n${outcome.body}`,
      display: true,
      details: { id, state: outcome.state },
    };
    const session = this.session;
    // During a run the result is queued, not run-starting: no reservation is
    // needed, and holding one would block another extension for its window.
    if (!wake || !session || this.busy) {
      this.pi.sendMessage(message, { deliverAs: "steer", triggerTurn: wake });
      return;
    }
    deliverWake(session, () =>
      this.pi.sendMessage(message, { deliverAs: "steer", triggerTurn: true }),
    );
  }
}

/**
 * Overlay listing the session's subagents, running ones first.
 *
 * Built on the shared overlay page: a bordered box with a
 * title, a summary, one line per child and an Escape hint. Rows are read from
 * the runner on every render, so elapsed time stays current; the order of the
 * rows is the one the view opened with, so a child that ends keeps its place
 * instead of moving down to the finished group mid-read. Enter opens one
 * child's activity and Escape walks back out. A running child gets the same
 * braille spinner as pi's working indicator; the animation runs only while one
 * is alive.
 */
class SubagentsOverlay implements Component {
  private readonly page: OverlayPage;
  private readonly nav: DrillDown;
  private readonly tui: TUI;
  private readonly theme: Theme;
  /** User keybindings, so the list moves with the keys every pi list uses. */
  private readonly keybindings: KeybindingsManager;
  private readonly readRows: () => SubagentRow[];
  /**
   * Ids in the order the view opened with.
   *
   * The runner orders rows by state and then by creation time, which is the
   * order to start from but not one to re-apply: a child that ends during the
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
    readRows: () => SubagentRow[],
    close: () => void,
  ) {
    this.tui = tui;
    this.theme = theme;
    this.keybindings = keybindings;
    this.readRows = readRows;
    this.close = close;
    this.order = readRows().map((row) => row.id);
    this.page = new OverlayPage(tui, theme, "Subagents");
    this.nav = new DrillDown(() => tui.requestRender());
    this.spinner = new Spinner(() => tui.requestRender());
    this.syncAnimation();
  }

  /**
   * The rows to show, in the order the view opened with.
   *
   * A child started while the view is open has no place yet, so it goes last,
   * where the runner order puts it.
   *
   * @returns One row per child, its fields read fresh.
   */
  private currentRows(): SubagentRow[] {
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
    // The session file belongs with the settings the summary repeats, not with
    // the steps below it.
    this.page.setSummary(
      detail
        ? [
            detailHeader(
              detail,
              this.spinner.marker(detail.state, this.theme),
              this.theme,
            ),
            ...(detail.sessionFile
              ? [
                  sessionLine(
                    detail.sessionFile,
                    Math.max(0, width - PAGE_PADDING_X * 2),
                    this.theme,
                  ),
                ]
              : []),
          ].join("\n")
        : summaryOf(rows, this.theme),
    );
    // The spawn moment is pinned, so scrolling the newest step into view never
    // hides when the child started.
    this.page.setHead(detail ? [startLine(detail, this.theme)] : []);
    if (detail) this.detailBody(detail, width);
    else this.listBody(rows, selected, width);
    return this.page.render(width);
  }

  invalidate(): void {
    this.syncAnimation();
    this.page.invalidate();
    this.tui.requestRender();
  }

  /** Re-render after the runner's state changed. */
  refresh(): void {
    this.syncAnimation();
    this.tui.requestRender();
  }

  /** Stop the animation when the overlay is closed. */
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
   * Render the list view, scrolled so the selected row stays visible.
   *
   * @param rows - Rows the overlay shows.
   * @param selected - Index of the selected row within all rows.
   * @param width - Overlay width, including the text padding.
   */
  private listBody(
    rows: readonly SubagentRow[],
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
   * Render one child's activity, scrolled to its newest steps by default.
   *
   * @param row - Child whose detail is open.
   * @param width - Overlay width, including the text padding.
   */
  private detailBody(row: SubagentRow, width: number): void {
    const lines = this.renderDetail(row, width);
    const hint = "Escape to go back";
    const capacity = this.page.measure(width, `${hint}, up/down scroll`);
    const start = this.nav.detailWindow(lines.length, capacity);
    this.page.setWindow(lines, start, capacity, hint, width);
  }

  /**
   * Render every subagent on one line each, with aligned columns.
   *
   * @param rows - Every row of the list.
   * @param width - Overlay width, including the text padding.
   * @param selected - Index of the selected row within all rows.
   * @returns One width-truncated line per subagent, the selected row on the
   *   selection background.
   */
  private renderRows(
    rows: readonly SubagentRow[],
    width: number,
    selected: number,
  ): string[] {
    const widths = alignWidths(rows);
    const inner = Math.max(0, width - PAGE_PADDING_X * 2);
    return rows.map((row, index) => {
      const column = columnsOf(row);
      return listRow(
        this.theme,
        padRight(column.id, widths.id),
        [
          this.spinner.marker(row.state, this.theme),
          this.theme.fg("muted", padLeft(column.status, widths.status)),
          this.theme.fg("muted", padLeft(column.elapsed, widths.elapsed)),
          this.theme.fg("dim", padRight(column.timeout, widths.timeout)),
          this.theme.fg("dim", padRight(column.model, widths.model)),
          this.theme.fg("dim", padRight(column.tools, widths.tools)),
          this.theme.fg("dim", padRight(column.cwd, widths.cwd)),
        ],
        inner,
        index === selected,
      );
    });
  }

  /**
   * Render the activity of one child, one step per line.
   *
   * The spawn moment is not a step: it sits in the detail's fixed head, so only
   * the steps themselves scroll.
   *
   * @param row - Child whose detail is open.
   * @param width - Overlay width, including the text padding.
   * @returns One width-truncated line per step, or the empty state.
   */
  private renderDetail(row: SubagentRow, width: number): string[] {
    const { theme } = this;
    const { steps } = row.activity;
    const inner = Math.max(0, width - PAGE_PADDING_X * 2);
    const kindWidth = Math.max(
      0,
      ...steps.map((step) => visibleWidth(stepKind(step))),
    );
    const lines = steps.map((step) => this.renderStep(step, kindWidth));
    if (steps.length === 0) {
      const empty =
        row.state === "running" ? "No activity yet." : "No activity recorded.";
      lines.push(theme.fg("dim", empty));
    }
    return lines.map((line) => truncateToWidth(line, inner, "...", true));
  }

  /**
   * Render one activity step: its start time, kind, label and open-state
   * suffix.
   *
   * @param step - Step to render.
   * @param kindWidth - Widest kind column of this render.
   * @returns The styled line, before width truncation.
   */
  private renderStep(step: ActivityStep, kindWidth: number): string {
    const { theme } = this;
    const label = step.kind === "think" ? charCount(step.chars) : step.label;
    const suffix = openSuffix(step);
    return [
      theme.fg("dim", clockTime(step.startedAt)),
      theme.fg("muted", padRight(stepKind(step), kindWidth)),
      label,
      suffix ? theme.fg("dim", suffix) : "",
    ]
      .filter(Boolean)
      .join(" ");
  }

  /** Start or stop the animation to match the rows. */
  private syncAnimation(): void {
    this.spinner.sync(
      this.currentRows().some((row) => row.state === "running"),
    );
  }
}

/**
 * Wrap a plain message, and optional details, as a tool result.
 *
 * @param text - Message for the agent.
 * @param details - Structured result data, empty for errors.
 * @returns Tool result carrying that message.
 */
function toolText(text: string, details: Record<string, unknown> = {}) {
  return { content: [{ type: "text" as const, text }], details };
}

/**
 * Normalize the `id` parameter: one id, a list, or nothing for all of them.
 *
 * @param id - Parameter value, already validated by the schema.
 * @returns Ids to act on, or undefined for "every subagent".
 */
function idsOf(id: string | string[] | undefined): string[] | undefined {
  if (id === undefined) return undefined;
  const ids = (Array.isArray(id) ? id : [id])
    .flatMap((entry) => entry.split(","))
    .map((entry) => entry.trim())
    .filter(Boolean);
  return ids.length > 0 ? ids : undefined;
}

/**
 * Check a requested timeout.
 *
 * @param timeoutSec - Timeout from the tool input, in seconds.
 * @returns Why the timeout is unusable, or undefined when it is fine.
 */
function timeoutProblem(timeoutSec: number): string | undefined {
  if (Number.isFinite(timeoutSec) && timeoutSec > 0) {
    return timeoutSec > MAX_TIMEOUT_SEC
      ? `The subagent timeout can be at most ${MAX_TIMEOUT_SEC}s.`
      : undefined;
  }
  return "The subagent timeout must be a positive number of seconds.";
}

/**
 * Build the `subagent` tool definition.
 *
 * @param runner - Session state that spawns and tracks the children.
 */
function subagentTool(
  runner: SubagentRunner,
): ToolDefinition<typeof SubagentParams> {
  return {
    name: "subagent",
    label: "Subagent",
    description: `Start a separate pi process with a fresh context to work on a task in the background. Returns immediately; the child reports later as a "${MARKER_EXAMPLE} ..." message, ended by its own \`${FINISH_TOOL}\` call. A run outlives pi: it pauses when pi exits and resumes in its own session with whatever running time its \`timeoutSec\` has left, so \`subagent_status\` can list a run started before the last restart; do not spawn that run again.`,
    promptSnippet: `Spawn a background pi subagent with its own prompt, tools and model`,
    promptGuidelines: [
      "Use `subagent` for a task that can run alongside your own work (an independent review, a long scan, a second opinion), or for several independent tasks in one turn, so they finish sooner and disagreement surfaces.",
      "Do not use `subagent` for work your next step depends on, for a task one or two tool calls would answer, or for a task you cannot describe concretely; do those locally.",
      "Give `subagent` a self-contained prompt whose answer is capped at 16 KB: state the files, the constraints and the result you expect, and ask for a file when it may write.",
      'For a fix you have already diagnosed, tell `subagent` the finding and the intended change; never write "fix what you find", which delegates the understanding instead of the work. Delegate verification of a concrete artifact; interpret an unclear finding yourself.',
      "Split write scopes: `subagent` children share this working tree with no isolation, so keep concurrent writers on disjoint files.",
      'Pass read-only `tools` such as ["read", "grep", "find"] to a research `subagent`, and give an editing child only the tools its change needs.',
      "For review and judging, give `subagent` a different `model` from the one that produced the work when one is available, ideally from another family: a reviewer sharing the author's model shares its blind spots.",
      `After calling \`subagent\`, do non-overlapping work: do not poll, do not redo the task, and never predict or invent its result before the ${MARKER_EXAMPLE} message arrives; use \`subagent_status\` instead of polling, and \`subagent_kill\` to drop a result you no longer need.`,
      `A child stays alive after its turns, so background work it started, such as a nested subagent, can wake it, and a child that never calls \`${FINISH_TOOL}\` keeps running until its \`timeoutSec\` passes: tell it to stop work it no longer needs.`,
      `Treat a ${MARKER_EXAMPLE} report as a claim to verify, not as proof the work is done.`,
    ],
    parameters: SubagentParams,
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const {
        prompt,
        tools = [],
        model = "",
        timeoutSec = DEFAULT_TIMEOUT_SEC,
      } = params;
      const problem = timeoutProblem(timeoutSec);
      if (problem) return toolText(problem);
      const cwd = params.cwd ? path.resolve(ctx.cwd, params.cwd) : ctx.cwd;
      const reserved = runner.reserveId(params.id, cwd);
      if ("problem" in reserved) return toolText(reserved.problem);
      const { id } = reserved;
      runner.claim(ctx.sessionManager.getSessionId());

      const selection = childSelection(model, ctx);
      runner.start({
        id,
        prompt,
        model: selection.model,
        thinking: selection.thinking,
        tools,
        cwd,
        timeoutSec,
      });

      const config = [
        `model=${selection.model || "default"}`,
        `tools=${tools.length > 0 ? tools.join(",") : "default"}`,
        `cwd=${cwd}`,
        `timeout=${timeoutSec}s`,
      ].join(", ");
      return toolText(
        `Subagent "${id}" started (${config}). Its result arrives as a "${marker(id)}" message.`,
        { id, cwd, model: selection.model, tools, timeoutSec },
      );
    },
  };
}

/**
 * Build the `subagent_status` tool definition.
 *
 * @param runner - Session state that owns the children.
 */
function statusTool(
  runner: SubagentRunner,
): ToolDefinition<typeof StatusParams> {
  return {
    name: "subagent_status",
    label: "Subagent status",
    description: `Report the subagents this session started, including ones a restart resumed: those still running with what each is doing right now, and the last ${FINISHED_HISTORY} that ended. Use it to check on a subagent instead of polling its result.`,
    parameters: StatusParams,
    async execute(_toolCallId, params) {
      return toolText(runner.status(idsOf(params.id)));
    },
  };
}

/**
 * Build the `subagent_kill` tool definition.
 *
 * @param runner - Session state that owns the children.
 */
function killTool(runner: SubagentRunner): ToolDefinition<typeof KillParams> {
  return {
    name: "subagent_kill",
    label: "Subagent kill",
    description:
      "Stop running subagents so their work no longer runs or reports; everything by default, or the named ids. Their output is discarded.",
    parameters: KillParams,
    async execute(_toolCallId, params) {
      const { stopped, unknown } = await runner.kill(idsOf(params.id));
      if (stopped.length === 0) {
        return toolText(
          unknown.length > 0
            ? `No running subagent named ${unknown.map(marker).join(", ")}.`
            : "No subagents are running.",
        );
      }
      const kept =
        unknown.length > 0
          ? ` Not running: ${unknown.map(marker).join(", ")}.`
          : "";
      return toolText(`Stopped ${stopped.map(marker).join(", ")}.${kept}`);
    },
  };
}

/**
 * Warn the child once its timeout approaches, so it can wrap up by itself.
 *
 * The parent still enforces the deadline; this only gives a model that forgot
 * to finish, or that is waiting on slow background work, one last chance to
 * deliver a usable answer instead of being cut off. `triggerTurn` wakes a child
 * that is idle on background work and `steer` reaches one that is mid-turn,
 * which is exactly the delivery this needs.
 *
 * @param pi - Extension API of the child process.
 * @param runner - Session state telling whether the child already finished.
 */
function warnBeforeDeadline(pi: ExtensionAPI, runner: SubagentRunner): void {
  // The parent counts the deadline from the spawn, which this load follows
  // closely enough for a warning that leads by seconds.
  const startedAt = Date.now();

  const timeoutSec = Number(process.env[TIMEOUT_ENV]);
  if (!Number.isFinite(timeoutSec) || timeoutSec <= 0) return;

  const leadSec = Math.min(
    timeoutSec / 2,
    Math.max(MIN_TIMEOUT_WARN_LEAD_SEC, timeoutSec * (1 - TIMEOUT_WARN_THRESH)),
  );
  const warning = setTimeout(
    () => {
      // A child that already asked to finish needs no warning.
      if (runner.finishRequested()) return;
      // Said from the clock, not the lead: a timer that fires late still
      // reports the time actually left.
      const leftSec = Math.max(
        0,
        Math.ceil((startedAt + timeoutSec * 1000 - Date.now()) / 1000),
      );
      pi.sendMessage(
        {
          customType: "subagent-deadline",
          content: `[subagent deadline] About ${leftSec}s of this session's ${timeoutSec}s budget is left. Wrap up now: finish what you can and call \`${FINISH_TOOL}\` with your best answer. Anything still pending is abandoned at the deadline, so start no background work that cannot finish in time.`,
          display: true,
        },
        { deliverAs: "steer", triggerTurn: true },
      );
    },
    Math.max(0, startedAt + (timeoutSec - leadSec) * 1000 - Date.now()),
  );
  // The warning must not be the reason the child stays alive, and process exit
  // cancels it: no shutdown hook is needed for it.
  warning.unref();
}

/**
 * Build the `subagent_finish` tool, which only a spawned child registers.
 *
 * Its session outlives its turns so async tools can wake it, which means the
 * process needs an explicit end: this tool is the only thing that closes it.
 * The answer travels in the argument, so the result ends the turn: a follow-up
 * turn would only repeat the report or add a sign-off.
 *
 * The snippet and guidelines describe only how the session ends: pi puts them
 * in the system prompt of every session that declares the tool, which is
 * exactly the spawned child. The child's role and deadline travel in the system
 * prompt that `childCommand` appends; neither belongs here.
 *
 * @param runner - Session state holding the end request.
 */
function finishTool(
  runner: SubagentRunner,
): ToolDefinition<typeof FinishParams> {
  return {
    name: FINISH_TOOL,
    label: "Finish subagent",
    description:
      "End this subagent session and report your answer to the parent verbatim. Anything still pending is abandoned.",
    promptSnippet:
      "End this subagent session and report your answer to the parent verbatim; a turn ending does not end the session.",
    promptGuidelines: [
      `You MUST call \`${FINISH_TOOL}\` when your answer is final: the parent receives the \`answer\` argument verbatim and nothing else, so put your complete report there.`,
      `Background work still pending when you call \`${FINISH_TOOL}\` is abandoned, so you may wait for anything you still need before finishing.`,
    ],
    parameters: FinishParams,
    async execute() {
      runner.requestFinish();
      // The answer travels in the argument, so the follow-up turn would only
      // add a sign-off.
      return {
        ...toolText(
          "Finishing: this session ends after this turn, and any background work still pending is abandoned.",
        ),
        terminate: true,
      };
    },
  };
}

/**
 * Build the `/subagents` command.
 *
 * @param runner - Session state the overlay shows.
 */
function subagentsCommand(runner: SubagentRunner) {
  return {
    description: "Show the session's subagents",
    handler: async (_args: string, ctx: ExtensionCommandContext) => {
      if (ctx.mode !== "tui") {
        ctx.ui.notify(runner.status(), "info");
        return;
      }
      await ctx.ui.custom<void>((tui, theme, keybindings, done) =>
        runner.createOverlay(tui, theme, keybindings, () => done()),
      );
      runner.detachOverlay();
    },
  };
}

/**
 * Custom message type of the nudge a child gets after a turn without a finish.
 */
const FINISH_REMINDER_TYPE = "subagent-finish-reminder";

/**
 * Nudge a child whose turn ended without calling `subagent_finish`.
 *
 * A turn ending does not end the child's session, so a model that writes its
 * report as plain text instead of calling the finish tool leaves the parent
 * waiting for an answer the child has already composed: it sits idle until the
 * deadline warning, or is cut off at the deadline with the report still in its
 * transcript. The reminder continues the same run at the settle boundary, so
 * the model still holds its report in context and one request is enough.
 *
 * @param pi - Extension API of the child process.
 * @param runner - Session state telling whether the child already finished.
 */
function remindMissingFinish(pi: ExtensionAPI, runner: SubagentRunner): void {
  /** Whether the turn that just ended emitted tool results. */
  let worked = false;
  /** Whether the current stretch of work was already reminded. */
  let reminded = false;

  pi.on("turn_end", (event) => {
    worked = event.toolResults.length > 0;
    if (worked) reminded = false;
  });

  pi.on("agent_before_settle", (event) => {
    if (worked || reminded || runner.finishRequested()) return;
    reminded = true;
    return {
      entries: [
        ...event.entries,
        {
          type: "custom_message",
          customType: FINISH_REMINDER_TYPE,
          content: `[subagent finish] Your turn ended without calling \`${FINISH_TOOL}\`, so the parent has not received your answer: this session stays open and idle until its deadline. Anything you wrote in a message did not reach the parent. Call \`${FINISH_TOOL}\` now with your complete report, unless you are still waiting on background work -- then wait and call it as soon as that work reports.`,
          display: false,
        },
      ],
      continue: true,
    };
  });
}

/**
 * End a spawned child when its model says the work is done.
 *
 * A child runs in RPC mode, so a turn with no tool calls no longer ends the
 * process: background work that reports after that turn, such as a nested
 * subagent, still wakes it, which is the point. The flip side is that the
 * process now has no natural end, so the model ends it: `subagent_finish` sets
 * the request, and the next settle -- after the turn's own answer is recorded --
 * closes the session.
 *
 * @param pi - Extension API of the child process.
 * @param runner - Runner holding the child's end request.
 */
function endChildWhenDone(pi: ExtensionAPI, runner: SubagentRunner): void {
  pi.on("agent_settled", async (_event, ctx) => {
    if (!runner.finishRequested()) return;
    // A turn that is already running has to report before the session ends.
    if (ctx.isIdle()) ctx.shutdown();
  });
}

/**
 * Register the subagent tools, `/subagents`, and the session hooks.
 *
 * @param pi - Extension API.
 */
export default function subagent(pi: ExtensionAPI) {
  const runner = new SubagentRunner(pi);

  pi.registerTool(subagentTool(runner));
  pi.registerTool(statusTool(runner));
  pi.registerTool(killTool(runner));
  pi.registerCommand("subagents", subagentsCommand(runner));
  // A run outlives the pi process that started it only as a record: every
  // shutdown pauses it, and the next open of this session resumes it.
  pi.on("session_shutdown", async () => {
    await runner.shutdown();
  });
  pi.on("session_start", (event, ctx) => {
    runner.restore(ctx, event.reason);
  });
  // A started run ends whichever wake was in flight, including another
  // extension's: the reservation covers the preflight gap, nothing more.
  pi.on("agent_start", (_event, ctx) => {
    runner.setBusy(true);
    releaseIdleWake(ctx.sessionManager);
  });
  pi.on("agent_settled", () => runner.setBusy(false));

  // A parent session is driven by its user, who decides when pi ends; a child
  // has nobody to close it, so it ends itself with the finish tool.
  if (process.env[CHILD_ENV] === "1") {
    pi.registerTool(finishTool(runner));
    endChildWhenDone(pi, runner);
    remindMissingFinish(pi, runner);
    warnBeforeDeadline(pi, runner);
  }
}
