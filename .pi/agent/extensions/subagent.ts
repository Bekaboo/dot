/**
 * Subagent tool.
 *
 * `subagent()` spawns a separate `pi --mode rpc --no-session` process for a
 * self-contained task, returns as soon as the child is running, and injects a
 * `[subagent <id>]` message into this session when the child finishes. The
 * child gets a fresh context window; its prompt, tools, model and working
 * directory are chosen per call.
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

import { type ChildProcess, spawn } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import type { StopReason } from "@earendil-works/pi-ai";
import type {
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
  JsonAgentSessionEvent,
  KeybindingsManager,
  Theme,
  ToolDefinition,
} from "@earendil-works/pi-coding-agent";
import { DynamicBorder } from "@earendil-works/pi-coding-agent";
import {
  type Component,
  Container,
  Text,
  type TUI,
  truncateToWidth,
  visibleWidth,
} from "@earendil-works/pi-tui";
import { Type } from "typebox";

import {
  bodyRows,
  hintLine,
  PAGE_PADDING_X,
  windowLabel,
} from "./utils/page.ts";
import { type RunState, Spinner } from "./utils/spinner.ts";

/** Custom message type used for subagent notifications. */
const NOTICE_TYPE = "subagent";

/**
 * Environment variable that marks a pi process as a spawned subagent.
 *
 * The child's copy of this extension reads it to take over ending the process;
 * a session a user drives must never end itself that way.
 */
const CHILD_ENV = "PI_SUBAGENT_CHILD";

/** Id of the `prompt` command sent to the child, echoed in its response. */
const PROMPT_ID = "prompt";

/** Id of the `prompt` command that carries a changed deadline to the child. */
const TIMEOUT_UPDATE_ID = "timeout-update";

/**
 * Command a spawned child registers to learn that its deadline changed.
 *
 * The parent enforces the deadline, but the child warns its own model before
 * it; the RPC protocol has no extension channel, so the new limit travels as
 * this command, which pi runs at once even while the child is mid-turn.
 */
const TIMEOUT_COMMAND = "subagent-timeout";

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

/** Longest line kept as a text step's label or tail, in characters. */
const ACTIVITY_LINE_CHARS = 80;

/** Longest argument summary kept for a tool step, in characters. */
const TOOL_SUMMARY_CHARS = 60;

/** Characters kept from an open text block, enough to derive its tail line. */
const TEXT_TAIL_BUFFER_CHARS = 400;

/** Kind column of the detail view's first line, the moment the child spawned. */
const START_KIND = "start";

/** Cursor in front of the selected `/subagents` row, as pi's select lists draw it. */
export const SELECTED_CURSOR = "→";

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
        'Model for the child, as "provider/id" or a bare id, optionally with a thinking level. Use `pi --list-models` to check available models. Omit to inherit this session\'s model and thinking level.',
    }),
  ),
  cwd: Type.Optional(
    Type.String({
      description:
        "Working directory for the child. Defaults to the current working directory.",
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

/** Schema for `subagent_update`; only the deadline can change for now. */
const UpdateParams = Type.Object({
  id: Type.String({ description: "Id of the running subagent to change." }),
  timeoutSec: Type.Number({
    description:
      "New wall-clock limit in seconds, counted from the child's start like the original, so it must exceed the time the child has already run. Raise it when the child was handed more work after it started, or is waiting on background work that needs longer than planned. Lower it when you want the result sooner: the child is warned about the nearer deadline and can wrap up and finish instead of using its full time.",
  }),
});

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
  /** Model as requested, empty when the child inherits pi's default. */
  model: string;
  /** Tools as requested, empty when the child gets pi's defaults. */
  tools: string[];
  cwd: string;
  /** Wall-clock limit the child was given, in seconds. */
  timeoutSec: number;
  startedAt: number;
  /** Creation order, so two children started in one millisecond stay ordered. */
  order: number;
  /** What the child has been doing, updated from its records. */
  activity: Activity;
}

/** A child that ended, kept briefly so `subagent_status` can report it. */
interface FinishedSubagent {
  id: string;
  /** Elapsed seconds at exit. */
  seconds: number;
  /** Spawn time in ms, the first line of the detail view. */
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
  /** Spawn time in ms, the first line of the detail view. */
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
  /** First line of a text block, or the argument summary of a tool call. */
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
  /** Characters kept from the open text block, enough to derive its tail. */
  textBuffer: string;
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
  return { phaseStartedAt: Date.now(), steps: [], textBuffer: "" };
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
 * @returns The first line of that value, cut short, or an empty string.
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
    ? edgeLine(value, false, TOOL_SUMMARY_CHARS)
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
 * kept; a text block keeps its first line as a label and the tail of a bounded
 * rolling buffer as its last line. Tool-call arguments stream while the reply
 * is still being prepared, so they open no step of their own.
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
      activity.textBuffer = "";
      startStep(activity, "text");
      return;
    case "text_delta": {
      let step = openStep(activity, (entry) => entry.kind === "text");
      if (!step) {
        activity.textBuffer = "";
        step = startStep(activity, "text");
      }
      activity.textBuffer = (activity.textBuffer + block.delta).slice(
        -TEXT_TAIL_BUFFER_CHARS,
      );
      step.chars += block.delta.length;
      // The first line grows over several deltas; follow it while the buffer
      // still holds the block's start.
      if (step.chars <= TEXT_TAIL_BUFFER_CHARS) {
        step.label = edgeLine(activity.textBuffer, false, ACTIVITY_LINE_CHARS);
      }
      step.tail = edgeLine(activity.textBuffer, true, ACTIVITY_LINE_CHARS);
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
  return step.label
    ? `${step.tool} \`${step.label}\` (${seconds}s)`
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
  const head = `${marker(job.id)} running for ${elapsedSec(job.startedAt)}s`;
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
 * @returns Resolves once the process has closed.
 */
function stopProcess(proc: ChildProcess): Promise<void> {
  return new Promise((resolve) => {
    if (proc.exitCode !== null || proc.signalCode !== null) return resolve();
    const settle = () => {
      clearTimeout(escalate);
      clearTimeout(giveUp);
      resolve();
    };
    const grace = killGraceMs();
    const escalate = setTimeout(() => proc.kill("SIGKILL"), grace);
    // A process that survives SIGKILL, or a handler that never fires, must not
    // keep the session alive on its own.
    const giveUp = setTimeout(settle, grace * 2);
    proc.once("close", settle);
    proc.kill("SIGTERM");
  });
}

/**
 * Summarize a finished child for its notification.
 *
 * @param lastTurn - Last assistant message of the child.
 * @param stderr - Child stderr, already capped.
 * @param failure - Why the child failed, or undefined for a successful run.
 * @param startedAt - Spawn time in ms, for the elapsed seconds.
 * @param timedOut - Whether the child ran out of wall-clock time, which is
 *   reported as its own outcome so `/subagents` names the cause at a glance.
 * @returns Terminal state, one-line summary and body of the notification.
 */
function outcomeOf(
  lastTurn: LastTurn,
  stderr: string,
  failure: string | undefined,
  startedAt: number,
  timedOut: boolean,
): Outcome {
  const seconds = elapsedSec(startedAt);
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
 * @param subagent - Id, model, thinking level, tools and timeout of the child.
 * @returns Command and arguments to spawn.
 */
function childCommand(subagent: {
  id: string;
  model: string;
  thinking: string;
  tools: string[];
  timeoutSec: number;
}): { command: string; args: string[] } {
  // Reuse the build that is already running, so a second pi on PATH cannot win.
  const command = process.env.PI_BIN ?? process.argv[1] ?? "pi";
  const args = ["--mode", "rpc", "--no-session", "--name", subagent.id];
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
 * Build the command that tells the child its deadline changed.
 *
 * @param timeoutSec - New wall-clock limit, counted from the child's start.
 * @returns One JSONL record for the child's stdin.
 */
function timeoutCommand(timeoutSec: number): string {
  return jsonLine({
    id: TIMEOUT_UPDATE_ID,
    type: "prompt",
    message: `/${TIMEOUT_COMMAND} ${timeoutSec}`,
  });
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
  // Only the task prompt starts the run; a deadline update is a command that
  // pi reports as handled, which is exactly what it should be.
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
function alignWidths(rows: SubagentRow[]): ColumnWidths {
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
 * Pad plain text on the right to a terminal width.
 *
 * @param text - Text without ANSI attributes.
 * @param width - Target terminal columns.
 * @returns The text followed by spaces, unchanged when already wide enough.
 */
function padRight(text: string, width: number): string {
  const missing = width - visibleWidth(text);
  return missing > 0 ? text + " ".repeat(missing) : text;
}

/**
 * Pad plain text on the left to a terminal width.
 *
 * @param text - Text without ANSI attributes.
 * @param width - Target terminal columns.
 * @returns The text preceded by spaces, unchanged when already wide enough.
 */
function padLeft(text: string, width: number): string {
  const missing = width - visibleWidth(text);
  return missing > 0 ? " ".repeat(missing) + text : text;
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
 * Header line of one child's detail view.
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
 * Index of the first row of a window that keeps the selection visible.
 *
 * @param selected - Index of the selected row within all rows.
 * @param total - Number of rows to show.
 * @param capacity - Rows the window holds.
 * @returns Index of the window's first row.
 */
function windowStart(
  selected: number,
  total: number,
  capacity: number,
): number {
  const last = Math.max(0, total - capacity);
  return Math.min(last, Math.max(0, selected - Math.floor(capacity / 2)));
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
  /** Per-child hooks that move a running child's deadline. */
  private timeoutSetters = new Map<string, (timeoutSec: number) => void>();
  /** Set once the session shuts down: pending notifications are dropped. */
  private shuttingDown = false;
  /**
   * Set when the child's model called `subagent_finish`.
   *
   * Only meaningful in a spawned child, where nothing else ends the session:
   * the model is the one who knows the task is over.
   */
  private finishAsked = false;
  /** Monotonic creation order for the overlay rows. */
  private nextOrder = 1;
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
   * Start the child and report its result when it exits.
   *
   * @param subagent - Id, model, thinking level, tools, working directory,
   *   timeout and prompt of the child.
   */
  start(
    subagent: Omit<
      RunningSubagent,
      "startedAt" | "order" | "prompt" | "activity"
    > & {
      prompt: string;
      /** Thinking level to force, empty to keep the model's own setting. */
      thinking: string;
    },
  ): void {
    const order = this.nextOrder++;
    const bridge = bridgeEnv(this.pi, subagent.id, order);
    const { command, args } = childCommand(subagent);
    const proc = spawn(command, args, {
      cwd: subagent.cwd,
      shell: false,
      stdio: ["pipe", "pipe", "pipe"],
      env: childEnv(subagent.timeoutSec, bridge),
    });

    this.children.set(subagent.id, proc);
    const running: RunningSubagent = {
      id: subagent.id,
      model: subagent.model,
      tools: subagent.tools,
      cwd: subagent.cwd,
      timeoutSec: subagent.timeoutSec,
      startedAt: Date.now(),
      order,
      activity: emptyActivity(),
    };
    this.running.set(running.id, running);
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
      this.timeoutSetters.delete(running.id);
      this.running.delete(running.id);
      const outcome = outcomeOf(
        lastTurn,
        stderrTail,
        failure,
        running.startedAt,
        timedOut,
      );
      this.remember({
        id: running.id,
        seconds: elapsedSec(running.startedAt),
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
    // counts from the spawn, so moving it keeps the time already spent.
    // Unref'd: this deadline must not keep the parent's event loop alive.
    const armTimeout = () => {
      clearTimeout(timeout);
      const remainingMs =
        running.startedAt + running.timeoutSec * 1000 - Date.now();
      timeout = setTimeout(
        () => {
          finish(`no result within its ${running.timeoutSec}s timeout`, true);
          void stopProcess(proc);
        },
        Math.max(0, remainingMs),
      );
      timeout.unref();
    };
    this.timeoutSetters.set(running.id, (timeoutSec) => {
      running.timeoutSec = timeoutSec;
      armTimeout();
      writeChild(proc, timeoutCommand(timeoutSec), appendStderr);
    });

    proc.on("error", (error) => finish(`spawn error: ${error.message}`));
    proc.on("close", (code, signal) =>
      finish(startFailure || failureOf(lastTurn, code, signal)),
    );
    // The readers are attached first, so a fast answer cannot arrive unread.
    writeChild(proc, promptCommand(subagent.prompt), appendStderr);
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
   * Describe every subagent this session knows about.
   *
   * @param only - Ids to report, or omitted for all of them.
   * @returns One line per subagent, or an explanation when nothing matched.
   */
  status(only?: string[]): string {
    const wanted = new Set(only ?? []);
    const matches = (id: string) => wanted.size === 0 || wanted.has(id);
    const running = [...this.running.values()]
      .filter((job) => matches(job.id))
      .map((job) => runningLine(job));
    const finished = this.finished
      .filter((job) => matches(job.id))
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
   * Describe every subagent this session knows about, oldest first.
   *
   * @returns One row per running child and per remembered finished child.
   */
  private rows(): SubagentRow[] {
    const running = [...this.running.values()].map((job) => ({
      id: job.id,
      state: "running" as const,
      order: job.order,
      seconds: elapsedSec(job.startedAt),
      startedAt: job.startedAt,
      model: job.model,
      tools: job.tools,
      cwd: job.cwd,
      timeoutSec: job.timeoutSec,
      activity: job.activity,
    }));
    const finished = this.finished.map((job) => ({
      id: job.id,
      state: job.state,
      order: job.order,
      seconds: job.seconds,
      startedAt: job.startedAt,
      model: job.model,
      tools: job.tools,
      cwd: job.cwd,
      timeoutSec: job.timeoutSec,
      activity: job.activity,
    }));
    return [...running, ...finished].sort((a, b) => a.order - b.order);
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
      this.remember({
        id,
        seconds: elapsedSec(job.startedAt),
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
      this.timeoutSetters.delete(id);
      waits.push(stop());
    }
    await Promise.all(waits);
    this.refreshOverlay();
    return { stopped, unknown };
  }

  /**
   * Move a running child's deadline, and send the child its new limit so it
   * warns in time.
   *
   * @param id - Id of the child to change.
   * @param timeoutSec - New wall-clock limit, counted from the child's start.
   * @returns What changed, or why nothing did.
   */
  updateTimeout(id: string, timeoutSec: number): string {
    const job = this.running.get(id);
    const setTimeoutSec = this.timeoutSetters.get(id);
    if (!job || !setTimeoutSec)
      return `No running subagent named ${marker(id)}.`;
    const ranSec = (Date.now() - job.startedAt) / 1000;
    if (timeoutSec <= ranSec) {
      return `${marker(id)} has already run for ${ranSec.toFixed(1)}s; give it a timeout above that.`;
    }
    const previous = job.timeoutSec;
    setTimeoutSec(timeoutSec);
    this.refreshOverlay();
    return `${marker(id)} timeout changed from ${previous}s to ${timeoutSec}s; about ${Math.round(timeoutSec - ranSec)}s are left.`;
  }

  /**
   * Kill every child and stop delivering results.
   *
   * Their results are dropped, so a reload says which ones were lost instead of
   * letting them vanish silently. `stopProcess` owns the signal escalation.
   *
   * @param reason - Why the session is shutting down.
   */
  async shutdown(reason: string): Promise<void> {
    this.shuttingDown = true;
    this.overlay?.dispose();
    this.overlay = undefined;
    const killed = [...this.running.keys()];
    this.running.clear();
    if (killed.length > 0 && reason === "reload") {
      // Reload keeps the session alive, so the loss is worth a notice; other
      // reasons tear the session down and nothing would read it.
      this.pi.sendMessage(
        {
          customType: NOTICE_TYPE,
          content: `Reload killed ${killed.length} running subagent(s): ${killed.map(marker).join(", ")}. Their results are lost; start them again if you still need them.`,
          display: true,
          details: { state: "killed", ids: killed },
        },
        { triggerTurn: false },
      );
    }
    await Promise.all(
      [...this.children.values()].map((proc) => stopProcess(proc)),
    );
    this.children.clear();
    this.stoppers.clear();
    this.timeoutSetters.clear();
  }

  /**
   * Queue the result at pi's next safe turn boundary, or wake an idle parent.
   *
   * Steering does not interrupt an in-flight request or tool execution. Pi
   * owns message ordering and continuation, so no idle polling is needed.
   */
  private deliver(id: string, outcome: Outcome): void {
    this.pi.sendMessage(
      {
        customType: NOTICE_TYPE,
        content: `${marker(id)} ${outcome.status}\n\n${outcome.body}`,
        display: true,
        details: { id, state: outcome.state },
      },
      { deliverAs: "steer", triggerTurn: true },
    );
  }
}

/**
 * Text of an overlay body and its hint line.
 *
 * `lines` already carries the blank line that separates the body from the
 * summary, and has been cut down to the rows the terminal leaves.
 */
interface OverlayBody {
  lines: string;
  footer: string;
}

/**
 * Size of the open detail view, so scrolling knows how far it can move.
 */
interface DetailViewport {
  /** Lines the detail view has in total. */
  total: number;
  /** Lines the window holds. */
  capacity: number;
}

/**
 * Overlay listing the session's subagents, oldest first.
 *
 * Laid out like the todo overlay: a bordered box with a title, a summary, one
 * line per child and an Escape hint. Rows are read from the runner on every
 * render, so elapsed time stays current; Enter opens one child's activity and
 * Escape walks back out. A running child gets the same braille spinner as pi's
 * working indicator; the animation runs only while one is alive. Bodies are cut
 * to the rows the terminal leaves, and the selected row or newest step stays in
 * view, so a short terminal keeps the box chrome and its hint visible.
 */
class SubagentsOverlay implements Component {
  private readonly container = new Container();
  private readonly summaryText: Text;
  private readonly rowsText: Text;
  private readonly footerText: Text;
  private readonly tui: TUI;
  private readonly theme: Theme;
  /** User keybindings, so the list moves with the keys every pi list uses. */
  private readonly keybindings: KeybindingsManager;
  private readonly readRows: () => SubagentRow[];
  private readonly close: () => void;
  private readonly spinner: Spinner;
  /** Index of the row the list view selected. */
  private selected = 0;
  /** Id whose detail view is open, or undefined while the list is shown. */
  private detailId: string | undefined;
  /**
   * First detail line the window shows, or undefined to follow the newest step.
   * Scrolling up pins it; scrolling to the end follows again.
   */
  private detailStart: number | undefined;
  /** Size of the detail view at the last render, so scrolling knows its bounds. */
  private detailView: DetailViewport | undefined;

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
    this.spinner = new Spinner(() => tui.requestRender());
    this.summaryText = new Text("", PAGE_PADDING_X, 0);
    this.rowsText = new Text("", PAGE_PADDING_X, 0);
    this.footerText = new Text("", PAGE_PADDING_X, 1);

    const border = () =>
      new DynamicBorder((text) => theme.fg("borderMuted", text));
    this.container.addChild(border());
    this.container.addChild(
      new Text(theme.fg("accent", theme.bold("Subagents")), PAGE_PADDING_X, 1),
    );
    this.container.addChild(this.summaryText);
    this.container.addChild(this.rowsText);
    this.container.addChild(this.footerText);
    this.container.addChild(border());
    this.syncAnimation();
  }

  render(width: number): string[] {
    const rows = this.readRows();
    this.selected = Math.min(this.selected, Math.max(0, rows.length - 1));
    const detail = rows.find((row) => row.id === this.detailId);
    if (!detail) {
      this.detailId = undefined;
      this.detailView = undefined;
    }
    this.summaryText.setText(
      detail
        ? detailHeader(
            detail,
            this.spinner.marker(detail.state, this.theme),
            this.theme,
          )
        : summaryOf(rows, this.theme),
    );
    const body = detail
      ? this.detailBody(detail, width)
      : this.listBody(rows, width);
    this.rowsText.setText(body.lines);
    this.footerText.setText(body.footer);
    return this.container.render(width);
  }

  invalidate(): void {
    this.syncAnimation();
    this.container.invalidate();
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
    if (this.keybindings.matches(data, "tui.select.cancel")) {
      if (this.detailId !== undefined) {
        this.detailId = undefined;
        this.detailView = undefined;
        this.tui.requestRender();
        return;
      }
      this.close();
      return;
    }
    if (this.detailId !== undefined) {
      this.scrollDetailView(data);
      return;
    }
    const rows = this.readRows();
    if (this.keybindings.matches(data, "tui.select.up")) {
      this.selected = Math.max(0, this.selected - 1);
      this.tui.requestRender();
      return;
    }
    if (this.keybindings.matches(data, "tui.select.down")) {
      this.selected = Math.min(Math.max(0, rows.length - 1), this.selected + 1);
      this.tui.requestRender();
      return;
    }
    const row = rows[this.selected];
    if (row && this.keybindings.matches(data, "tui.select.confirm")) {
      this.detailId = row.id;
      this.detailStart = undefined;
      this.detailView = undefined;
      this.tui.requestRender();
    }
  }

  /**
   * Move the open detail view with the list keys.
   *
   * @param data - Input the overlay received.
   */
  private scrollDetailView(data: string): void {
    const page = Math.max(1, this.detailView?.capacity ?? 1);
    const moves: [string, number][] = [
      ["tui.select.up", -1],
      ["tui.select.down", 1],
      ["tui.select.pageUp", -page],
      ["tui.select.pageDown", page],
    ];
    for (const [action, lines] of moves) {
      if (!this.keybindings.matches(data, action)) continue;
      this.scrollDetail(lines);
      return;
    }
  }

  /**
   * Scroll the detail view, and follow the newest step again at its end.
   *
   * @param lines - Lines to move; negative moves towards older steps.
   */
  private scrollDetail(lines: number): void {
    const view = this.detailView;
    if (!view) return;
    const last = Math.max(0, view.total - view.capacity);
    if (last === 0) return;
    // Resolve a followed tail before moving, so repeated keys add up even when
    // the TUI has not rendered between them.
    const from = this.detailStart ?? last;
    const next = Math.max(0, Math.min(last, from + lines));
    this.detailStart = next >= last ? undefined : next;
    this.tui.requestRender();
  }

  /**
   * Rows the body may fill at this width, without the box chrome.
   *
   * The overlay takes the editor's place between the transcript and pi's
   * footer, so the terminal height minus pi's own rows is all it can use
   * before the viewport clips its last lines.
   *
   * @param width - Overlay width, including the text padding.
   * @param hint - Hint the box will show, measured without its row count.
   * @returns Lines available for the body, or 0 when only the chrome fits.
   */
  private bodyCapacity(width: number, hint: string): number {
    this.rowsText.setText("");
    this.footerText.setText(hintLine(this.theme, hint, width));
    return bodyRows(
      () => this.container.render(width).length,
      this.tui.terminal.rows,
    );
  }

  /**
   * Render the list view, scrolled so the selected row stays visible.
   *
   * @param rows - Rows the overlay shows.
   * @param width - Overlay width, including the text padding.
   * @returns The body text and its hint line.
   */
  private listBody(rows: SubagentRow[], width: number): OverlayBody {
    if (rows.length === 0) {
      return {
        lines: "",
        footer: hintLine(this.theme, "Press Escape to close", width),
      };
    }
    const hint = "Enter for details, Escape to close";
    const capacity = this.bodyCapacity(width, hint);
    const start = windowStart(this.selected, rows.length, capacity);
    const shown = rows.slice(start, start + capacity);
    return {
      lines:
        shown.length > 0 ? `\n${this.renderRows(shown, width, start)}` : "",
      footer: hintLine(
        this.theme,
        `${hint}${windowLabel(start, shown.length, rows.length)}`,
        width,
      ),
    };
  }

  /**
   * Render one child's activity, scrolled to its newest steps by default.
   *
   * @param row - Child whose detail is open.
   * @param width - Overlay width, including the text padding.
   * @returns The body text and its hint line.
   */
  private detailBody(row: SubagentRow, width: number): OverlayBody {
    const lines = this.renderDetail(row, width);
    const hint = "Escape to go back";
    const scrollHint = `${hint}, up/down scroll`;
    const capacity = this.bodyCapacity(width, scrollHint);
    const last = Math.max(0, lines.length - capacity);
    const start =
      this.detailStart === undefined ? last : Math.min(this.detailStart, last);
    const shown = lines.slice(start, start + capacity);
    this.detailView = { total: lines.length, capacity };
    return {
      lines: shown.length > 0 ? `\n${shown.join("\n")}` : "",
      footer: hintLine(
        this.theme,
        `${lines.length > capacity ? scrollHint : hint}${windowLabel(start, shown.length, lines.length)}`,
        width,
      ),
    };
  }

  /**
   * Render every subagent on one line each, with aligned columns.
   *
   * @param rows - Rows the window shows.
   * @param width - Overlay width, including the text padding.
   * @param first - Index of the first row within all rows, so the cursor stays
   *   on the selection while the list is scrolled.
   * @returns One width-truncated line per subagent.
   */
  private renderRows(
    rows: SubagentRow[],
    width: number,
    first: number,
  ): string {
    const widths = alignWidths(rows);
    const inner = Math.max(0, width - PAGE_PADDING_X * 2);
    return rows
      .map((row, index) =>
        truncateToWidth(
          this.renderRow(row, widths, index + first === this.selected),
          inner,
          "...",
          true,
        ),
      )
      .join("\n");
  }

  /**
   * Render one subagent as its id, spinner or state marker, and aligned
   * settings.
   *
   * @param row - Subagent to render.
   * @param widths - Column widths shared by every row of this render.
   * @param selected - Whether the list view has this row selected.
   * @returns The styled line, before width truncation.
   */
  private renderRow(
    row: SubagentRow,
    widths: ColumnWidths,
    selected: boolean,
  ): string {
    const { theme } = this;
    const column = columnsOf(row);
    const id = padRight(column.id, widths.id);
    // Every row reserves the cursor column, so selection never shifts it.
    const cursor = selected ? theme.fg("accent", SELECTED_CURSOR) : " ";
    return [
      cursor,
      selected ? theme.fg("accent", theme.bold(id)) : theme.bold(id),
      this.spinner.marker(row.state, theme),
      theme.fg("muted", padLeft(column.status, widths.status)),
      theme.fg("muted", padLeft(column.elapsed, widths.elapsed)),
      theme.fg("dim", padRight(column.timeout, widths.timeout)),
      theme.fg("dim", padRight(column.model, widths.model)),
      theme.fg("dim", padRight(column.tools, widths.tools)),
      theme.fg("dim", padRight(column.cwd, widths.cwd)),
    ].join(" ");
  }

  /**
   * Render the activity of one child, one step per line.
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
      ...[START_KIND, ...steps.map(stepKind)].map(visibleWidth),
    );
    const start = [
      theme.fg("dim", clockTime(row.startedAt)),
      theme.fg("muted", padRight(START_KIND, kindWidth)),
    ].join(" ");
    const lines = [
      start,
      ...steps.map((step) => this.renderStep(step, kindWidth)),
    ];
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
    this.spinner.sync(this.readRows().some((row) => row.state === "running"));
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
    description: `Start a separate pi process with a fresh context to work on a task in the background. Returns immediately; the child's answer arrives later as a "${MARKER_EXAMPLE} ..." message. The child ends itself by calling its own \`${FINISH_TOOL}\` tool, so background work it started, such as a nested subagent, can wake it after a turn and be reported too. A child still running at its timeout is stopped and reported as timed out, so a stuck child cannot go silent.`,
    promptSnippet: `Spawn a background pi subagent with its own prompt, tools and model; its result arrives later as a ${MARKER_EXAMPLE} message. A child may wait on background work it started, such as a nested subagent, before it reports, and is stopped at its timeout.`,
    promptGuidelines: [
      "Use `subagent` for one task that can run alongside your own work, such as an independent review, a long scan, or a second opinion.",
      "Use `subagent` for several independent tasks in one turn, such as research in separate areas, a change read from several perspectives, or verification from several angles, so they finish sooner and disagreement surfaces.",
      "Do not use `subagent` for work your next step depends on, for a task one or two tool calls would answer, or for a task you cannot describe concretely; do those locally.",
      "Give `subagent` a self-contained prompt: it starts with no conversation and returns one answer capped at 16 KB, so state the files, the constraints, and the result you expect back, and ask for a file when it may write.",
      'For a fix you have already diagnosed, tell `subagent` the finding and the intended change; never write "fix what you find", which delegates the understanding instead of the work. Delegate verification of a concrete artifact; interpret an unclear finding yourself.',
      "Split write scopes before spawning: `subagent` children share this working tree and can edit it, with no isolation, so keep concurrent writers on disjoint files.",
      'Pass read-only `tools` such as ["read", "grep", "find"] to a research `subagent`, and give an editing child only the tools its change needs.',
      "For review and judging, especially code review, give `subagent` a different `model` from the one that produced the work when one is available, ideally from another family: a reviewer that shares the author's model shares its blind spots.",
      `After calling \`subagent\`, do non-overlapping work: do not poll, do not redo the task, and never predict or invent its result before the ${MARKER_EXAMPLE} message arrives.`,
      "Use `subagent_status` to answer whether a child still runs, not to poll, and `subagent_kill` to stop one whose result you no longer need.",
      "Use `subagent_update` to give a running child more time when its work grew after the start, instead of letting it time out or starting it again.",
      `A child stays alive after its turns, so background work it started, such as a nested subagent, can wake it; it reports by calling its own \`${FINISH_TOOL}\` tool. A child that never calls it keeps running until its \`timeoutSec\` passes, so raise that timeout when the child is meant to wait on long background work, and tell it to stop background work it no longer needs.`,
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
    description: `Report the subagents this session started: those still running, with what each is doing right now (waiting for the model, writing, thinking, running a tool, or settled and idle), and the last ${FINISHED_HISTORY} that ended. Use it to check on a subagent instead of polling its result.`,
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
      "Stop running subagents so their work no longer runs or reports. Kills everything by default; name one id or a list to be selective. Their output is discarded.",
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
 * Build the `subagent_update` tool definition.
 *
 * @param runner - Session state that owns the children.
 */
function updateTool(
  runner: SubagentRunner,
): ToolDefinition<typeof UpdateParams> {
  return {
    name: "subagent_update",
    label: "Subagent update",
    description:
      "Change a running subagent's configuration. Only its wall-clock limit (`timeoutSec`) can be changed for now, and the child is sent the new limit.",
    parameters: UpdateParams,
    async execute(_toolCallId, params) {
      const { id, timeoutSec } = params;
      const problem = timeoutProblem(timeoutSec);
      if (problem) return toolText(problem);
      return toolText(runner.updateTimeout(id.trim(), timeoutSec));
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
 * The parent may move the deadline later or earlier through `TIMEOUT_COMMAND`;
 * the warning then follows it, and the model is told the new limit at its next
 * request without being woken for it.
 *
 * @param pi - Extension API of the child process.
 * @param runner - Session state telling whether the child already finished.
 */
function warnBeforeDeadline(pi: ExtensionAPI, runner: SubagentRunner): void {
  // The parent counts the deadline from the spawn, which this load follows
  // closely enough for a warning that leads by seconds.
  const startedAt = Date.now();
  let warning: ReturnType<typeof setTimeout> | undefined;

  const arm = (timeoutSec: number) => {
    clearTimeout(warning);
    const leadSec = Math.min(
      timeoutSec / 2,
      Math.max(
        MIN_TIMEOUT_WARN_LEAD_SEC,
        timeoutSec * (1 - TIMEOUT_WARN_THRESH),
      ),
    );
    warning = setTimeout(
      () => {
        // A child that already asked to finish needs no warning.
        if (runner.finishRequested()) return;
        // Said from the clock, not the lead: a deadline moved into the lead
        // window warns at once with less time left than the lead.
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
  };

  const initial = Number(process.env[TIMEOUT_ENV]);
  if (Number.isFinite(initial) && initial > 0) arm(initial);

  pi.registerCommand(TIMEOUT_COMMAND, {
    description: "Move this subagent's deadline; sent by the parent session",
    handler: async (args: string) => {
      const timeoutSec = Number(args.trim());
      if (!Number.isFinite(timeoutSec) || timeoutSec <= 0) return;
      arm(timeoutSec);
      pi.sendMessage(
        {
          customType: "subagent-deadline",
          content: `[subagent deadline] The parent changed this session's wall-clock limit to ${timeoutSec}s, counted from its start.`,
          display: true,
        },
        { triggerTurn: false },
      );
    },
  });
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
 * Register the subagent tools, `/subagents`, and the shutdown hook.
 *
 * @param pi - Extension API.
 */
export default function subagent(pi: ExtensionAPI) {
  const runner = new SubagentRunner(pi);

  pi.registerTool(subagentTool(runner));
  pi.registerTool(statusTool(runner));
  pi.registerTool(killTool(runner));
  pi.registerTool(updateTool(runner));
  pi.registerCommand("subagents", subagentsCommand(runner));
  // Async so the handler's promise is awaited: pi waits for children to close.
  pi.on("session_shutdown", async (event) => {
    await runner.shutdown(event.reason);
  });

  // A parent session is driven by its user, who decides when pi ends; a child
  // has nobody to close it, so it ends itself with the finish tool.
  if (process.env[CHILD_ENV] === "1") {
    pi.registerTool(finishTool(runner));
    endChildWhenDone(pi, runner);
    warnBeforeDeadline(pi, runner);
  }
}
