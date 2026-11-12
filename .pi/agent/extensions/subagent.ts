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
 * with no tool calls, so a timer or nested subagent that reports afterwards
 * still wakes it. Since the process has no natural end any more, the child's
 * own instance of this extension ends it when the model calls the
 * `subagent_finish` tool.
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
  Theme,
  ToolDefinition,
} from "@earendil-works/pi-coding-agent";
import { DynamicBorder } from "@earendil-works/pi-coding-agent";
import {
  type Component,
  Container,
  matchesKey,
  Text,
  type TUI,
  truncateToWidth,
  visibleWidth,
} from "@earendil-works/pi-tui";
import { Type } from "typebox";

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

/**
 * Tool a spawned child uses to end its session by itself.
 *
 * Named rather than inlined: the child asserts it at session start, and its
 * system prompt tells the model when to call it.
 */
const FINISH_TOOL = "subagent_finish";

/** How much of the child's final answer to put in a notification, in bytes. */
const OUTPUT_CAP_BYTES = 16 * 1024;

/** How much of the child's stderr to keep for a failure report, in bytes. */
const STDERR_CAP_BYTES = 2 * 1024;

/** Grace period before a child that ignored SIGTERM gets SIGKILL, in ms. */
const KILL_GRACE_MS = 2_000;

/** Largest delay `setTimeout` honors; anything above it would fire at once. */
const MAX_TIMER_MS = 2 ** 31 - 1;

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
 * Generous, because a child may legitimately wait on background work it
 * started; it exists so a stuck child still reports instead of living on.
 */
const DEFAULT_TIMEOUT_SEC = 3_600;

/** Environment variable carrying a child's timeout, so it can warn itself. */
const TIMEOUT_ENV = "PI_SUBAGENT_TIMEOUT_SEC";

/** Fraction of its timeout after which a child is warned to wrap up. */
const WARN_AT = 0.8;

/**
 * Shortest warning lead worth a model turn, in seconds.
 *
 * A percentage of a short timeout would land too close to the deadline to be
 * useful, so the warning moves earlier instead.
 */
const MIN_WARN_LEAD_SEC = 10;

/** Longest single JSONL record kept from the child, in bytes. */
const MAX_RECORD_BYTES = 8 * 1024 * 1024;

/** How many finished children are remembered for `subagent_status`. */
const FINISHED_HISTORY = 10;

/** Braille frames pi's built-in working spinner uses. */
const SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

/** Spinner frame interval in ms, matching pi's built-in working indicator. */
const SPINNER_INTERVAL_MS = 80;

/** Horizontal padding inside the `/subagents` overlay. */
const OVERLAY_PADDING_X = 2;

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
        'Model for the child, as "provider/id" or a bare id, optionally with ":high" and similar for the thinking level. Omit to inherit this session\'s model and thinking level.',
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
      description: `Wall-clock limit for the child, in seconds. The child is stopped and reported as failed when it passes, which bounds a child that never calls its own finish tool. Defaults to ${DEFAULT_TIMEOUT_SEC}.`,
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

/** Schema for `subagent_finish`, which needs no arguments. */
const FinishParams = Type.Object({});

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
}

/** A child that ended, kept briefly so `subagent_status` can report it. */
interface FinishedSubagent {
  id: string;
  /** Elapsed seconds at exit. */
  seconds: number;
  /** Outcome word: done, fail, or kill. */
  state: string;
  /** Failure text, when the child did not finish cleanly. */
  reason?: string;
  model: string;
  tools: string[];
  cwd: string;
  /** Wall-clock limit the child was given, in seconds. */
  timeoutSec: number;
  /** Creation order, so two children started in one millisecond stay ordered. */
  order: number;
}

/** One line of the `/subagents` overlay. */
interface SubagentRow {
  id: string;
  /** Outcome word: work, done, fail, or kill. */
  state: string;
  /** Creation order, so two children started in one millisecond stay ordered. */
  order: number;
  /** Elapsed seconds: live while running, at exit once finished. */
  seconds: number;
  model: string;
  tools: string[];
  cwd: string;
  /** Wall-clock limit the child was given, in seconds. */
  timeoutSec: number;
}

/** What the last assistant message of a child says, once its records are parsed. */
interface LastTurn {
  /** Answer text of that message, or an empty string. */
  answer: string;
  /** Terminal stop reason, such as "error", "length" or "aborted". */
  stopReason?: StopReason;
  /** Provider or pi error text, when the turn failed. */
  errorMessage?: string;
}

/** Terminal state of a child, as its notification reports it. */
interface Outcome {
  state: "done" | "fail";
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
 * Read the latest assistant text out of one JSONL record.
 *
 * Only completed `message_end` records carry the authoritative answer, so the
 * last assistant message alone is kept.
 *
 * @param lastTurn - Last assistant message, updated in place.
 * @param record - Parsed `--mode json` record.
 */
function absorbRecord(lastTurn: LastTurn, record: unknown): void {
  const event = record as JsonAgentSessionEvent;
  if (event.type !== "message_end" || event.message.role !== "assistant")
    return;
  const message = event.message;
  lastTurn.answer = truncateBytes(
    message.content
      .filter(
        (part): part is { type: "text"; text: string } => part.type === "text",
      )
      .map((part) => part.text)
      .join("\n"),
    OUTPUT_CAP_BYTES,
  );
  lastTurn.stopReason = message.stopReason;
  lastTurn.errorMessage = message.errorMessage;
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
 * @returns Terminal state, one-line summary and body of the notification.
 */
function outcomeOf(
  lastTurn: LastTurn,
  stderr: string,
  failure: string | undefined,
  startedAt: number,
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
  return {
    state: "fail",
    status: `failed after ${seconds}s: ${reason}`,
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
 * Build the invocation for the child pi process.
 *
 * The child runs in RPC mode: its prompt travels on stdin, and the process stays
 * alive between turns so async tools can wake it. Nothing is passed as a
 * positional argument, because RPC mode rejects `@file` prompts and expects
 * commands on stdin instead.
 *
 * The child's role and its contract for ending the session travel in the
 * `subagent_finish` declaration, which only a child ever sees; nothing is
 * appended to its system prompt here.
 *
 * The call's id also names the child's session. Pi's session name is one field
 * that `/name`, `--name` and `pi.setSessionName()` all write, so naming the
 * child here makes every reader of it agree: notifications and `status` say
 * `<id>`, and pi-intercom publishes `<id>` as the child's address instead of
 * the `subagent-chat-<session id>` fallback an unnamed session gets. Without
 * this, a parent can only tell its children apart by model, directory or
 * context size, and none of that survives two children that share them.
 *
 * @param subagent - Id, model, thinking level and tools of the child.
 * @returns Command and arguments to spawn.
 */
function childCommand(subagent: {
  id: string;
  model: string;
  thinking: string;
  tools: string[];
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
    type?: unknown;
    command?: unknown;
    success?: unknown;
    error?: unknown;
    data?: { disposition?: unknown };
  };
  if (response.type !== "response" || response.command !== "prompt")
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
 * Describe a child's model, tools and working directory on one line.
 *
 * @param job - Model, tools and working directory of the child.
 * @returns Text such as "qoder/Fast, tools=read,bash, /work".
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
    `timeout=${job.timeoutSec}s`,
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
 * @param seconds - Wall-clock limit the child was given, zero when unknown.
 * @returns Text such as "timeout=600s".
 */
function timeoutLabel(seconds: number): string {
  return seconds > 0 ? `timeout=${seconds}s` : "timeout=-";
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
  const running = rows.filter((row) => row.state === "work").length;
  return theme.fg(
    "muted",
    `${running} running, ${rows.length - running} finished`,
  );
}

/**
 * Glyph and color for a subagent's state, with the spinner while it runs.
 *
 * @param state - `work`, or the terminal state of a finished child.
 * @param frame - Current spinner frame index.
 * @param theme - Active theme.
 * @returns The styled marker.
 */
function stateMarker(state: string, frame: number, theme: Theme): string {
  switch (state) {
    case "work":
      return theme.fg("accent", SPINNER_FRAMES[frame % SPINNER_FRAMES.length]);
    case "done":
      return theme.fg("success", "✓");
    case "fail":
      return theme.fg("error", "✗");
    default:
      return theme.fg("dim", "·");
  }
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
    subagent: Omit<RunningSubagent, "startedAt" | "order" | "prompt"> & {
      prompt: string;
      /** Thinking level to force, empty to keep the model's own setting. */
      thinking: string;
    },
  ): void {
    const { command, args } = childCommand(subagent);
    const proc = spawn(command, args, {
      cwd: subagent.cwd,
      shell: false,
      stdio: ["pipe", "pipe", "pipe"],
      // The child's own copy of this extension ends the process once its work
      // is done; the marker tells it that is its job rather than the user's.
      env: {
        ...process.env,
        [CHILD_ENV]: "1",
        // The child warns itself near the deadline; it needs the same number
        // the parent enforces.
        [TIMEOUT_ENV]: String(subagent.timeoutSec),
      },
    });

    this.children.set(subagent.id, proc);
    const running: RunningSubagent = {
      id: subagent.id,
      model: subagent.model,
      tools: subagent.tools,
      cwd: subagent.cwd,
      timeoutSec: subagent.timeoutSec,
      startedAt: Date.now(),
      order: this.nextOrder++,
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
    const finish = (failure: string | undefined) => {
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
      const outcome = outcomeOf(
        lastTurn,
        stderrTail,
        failure,
        running.startedAt,
      );
      this.remember({
        id: running.id,
        seconds: elapsedSec(running.startedAt),
        state: outcome.state,
        reason: failure,
        model: running.model,
        tools: running.tools,
        cwd: running.cwd,
        timeoutSec: running.timeoutSec,
        order: running.order,
      });
      this.refreshOverlay();
      this.deliver(running.id, outcome);
    };

    this.stoppers.set(running.id, () => {
      stopped = true;
      return stopProcess(proc);
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
    // A child that never calls its own finish tool, or that hangs on an
    // extension error, still has to report instead of living on.
    timeout = setTimeout(
      () => {
        finish(`no result within its ${subagent.timeoutSec}s timeout`);
        void stopProcess(proc);
      },
      Math.min(subagent.timeoutSec * 1000, MAX_TIMER_MS),
    );
    timeout.unref();
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
      .map((job) => {
        const seconds = elapsedSec(job.startedAt);
        return `${marker(job.id)} running for ${seconds}s (${subagentSettings(job)})`;
      });
    const finished = this.finished
      .filter((job) => matches(job.id))
      .map(
        (job) =>
          `${marker(job.id)} ${job.state} after ${job.seconds}s (timeout=${job.timeoutSec}s)${job.reason ? `: ${job.reason}` : ""}`,
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
   * @param close - Closes the overlay.
   * @returns The overlay component.
   */
  createOverlay(tui: TUI, theme: Theme, close: () => void): SubagentsOverlay {
    const overlay = new SubagentsOverlay(tui, theme, () => this.rows(), close);
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
      state: "work",
      order: job.order,
      seconds: elapsedSec(job.startedAt),
      model: job.model,
      tools: job.tools,
      cwd: job.cwd,
      timeoutSec: job.timeoutSec,
    }));
    const finished = this.finished.map((job) => ({
      id: job.id,
      state: job.state,
      order: job.order,
      seconds: job.seconds,
      model: job.model,
      tools: job.tools,
      cwd: job.cwd,
      timeoutSec: job.timeoutSec,
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
      const stop = this.stoppers.get(id);
      if (!stop) {
        unknown.push(id);
        continue;
      }
      stopped.push(id);
      const job = this.running.get(id);
      this.remember({
        id,
        seconds: job ? elapsedSec(job.startedAt) : 0,
        state: "kill",
        model: job?.model ?? "",
        tools: job?.tools ?? [],
        cwd: job?.cwd ?? "",
        timeoutSec: job?.timeoutSec ?? 0,
        order: job?.order ?? 0,
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
          content: `Reload cancelled ${killed.length} running subagent(s): ${killed.map(marker).join(", ")}. Their results are lost; start them again if you still need them.`,
          display: true,
          details: { state: "cancelled", ids: killed },
        },
        { triggerTurn: false },
      );
    }
    await Promise.all(
      [...this.children.values()].map((proc) => stopProcess(proc)),
    );
    this.children.clear();
    this.stoppers.clear();
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
 * Overlay listing the session's subagents, oldest first.
 *
 * Laid out like the todo overlay: a bordered box with a title, a summary, one
 * line per child and an Escape hint. Rows are read from the runner on every
 * render, so elapsed time stays current. A running child
 * gets the same braille spinner as pi's working indicator; the animation runs
 * only while one is alive.
 */
class SubagentsOverlay implements Component {
  private readonly container = new Container();
  private readonly summaryText: Text;
  private readonly rowsText: Text;
  private readonly tui: TUI;
  private readonly theme: Theme;
  private readonly readRows: () => SubagentRow[];
  private readonly close: () => void;
  private frame = 0;
  private timer: ReturnType<typeof setInterval> | undefined;

  constructor(
    tui: TUI,
    theme: Theme,
    readRows: () => SubagentRow[],
    close: () => void,
  ) {
    this.tui = tui;
    this.theme = theme;
    this.readRows = readRows;
    this.close = close;
    this.summaryText = new Text("", OVERLAY_PADDING_X, 0);
    this.rowsText = new Text("", OVERLAY_PADDING_X, 0);

    const border = () =>
      new DynamicBorder((text) => theme.fg("borderMuted", text));
    this.container.addChild(border());
    this.container.addChild(
      new Text(
        theme.fg("accent", theme.bold("Subagents")),
        OVERLAY_PADDING_X,
        1,
      ),
    );
    this.container.addChild(this.summaryText);
    this.container.addChild(this.rowsText);
    this.container.addChild(
      new Text(theme.fg("dim", "Press Escape to close"), OVERLAY_PADDING_X, 1),
    );
    this.container.addChild(border());
    this.syncAnimation();
  }

  render(width: number): string[] {
    const rows = this.readRows();
    this.summaryText.setText(summaryOf(rows, this.theme));
    this.rowsText.setText(
      rows.length > 0 ? `\n${this.renderRows(rows, width)}` : "",
    );
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
    this.stopAnimation();
  }

  handleInput(data: string): void {
    if (matchesKey(data, "escape") || matchesKey(data, "ctrl+c")) {
      this.close();
    }
  }

  /**
   * Render every subagent on one line each, with aligned columns.
   *
   * @param rows - Rows the overlay shows.
   * @param width - Overlay width, including the text padding.
   * @returns One width-truncated line per subagent.
   */
  private renderRows(rows: SubagentRow[], width: number): string {
    const widths = alignWidths(rows);
    const inner = Math.max(0, width - OVERLAY_PADDING_X * 2);
    return rows
      .map((row) =>
        truncateToWidth(this.renderRow(row, widths), inner, "...", true),
      )
      .join("\n");
  }

  /**
   * Render one subagent as spinner or state marker and aligned settings.
   *
   * @param row - Subagent to render.
   * @param widths - Column widths shared by every row of this render.
   * @returns The styled line, before width truncation.
   */
  private renderRow(row: SubagentRow, widths: ColumnWidths): string {
    const { theme } = this;
    const column = columnsOf(row);
    return [
      stateMarker(row.state, this.frame, theme),
      theme.bold(padRight(column.id, widths.id)),
      theme.fg("muted", padLeft(column.status, widths.status)),
      theme.fg("muted", padLeft(column.elapsed, widths.elapsed)),
      theme.fg("dim", padRight(column.timeout, widths.timeout)),
      theme.fg("dim", padRight(column.model, widths.model)),
      theme.fg("dim", padRight(column.tools, widths.tools)),
      theme.fg("dim", padRight(column.cwd, widths.cwd)),
    ].join(" ");
  }

  /** Start or stop the animation to match the rows. */
  private syncAnimation(): void {
    if (this.readRows().some((row) => row.state === "work")) {
      this.startAnimation();
      return;
    }
    this.stopAnimation();
  }

  private startAnimation(): void {
    if (this.timer) return;
    this.timer = setInterval(() => {
      this.frame = (this.frame + 1) % SPINNER_FRAMES.length;
      this.tui.requestRender();
    }, SPINNER_INTERVAL_MS);
  }

  private stopAnimation(): void {
    if (!this.timer) return;
    clearInterval(this.timer);
    this.timer = undefined;
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
    description: `Start a separate pi process with a fresh context to work on a task in the background. Returns immediately; the child's answer arrives later as a "${MARKER_EXAMPLE} ..." message. The child ends itself by calling its own \`${FINISH_TOOL}\` tool, so background work it started, such as a timer or a nested subagent, can wake it after a turn and be reported too. A child still running at its timeout is stopped and reported as failed, so a stuck child cannot go silent.`,
    promptSnippet: `Spawn a background pi subagent with its own prompt, tools and model; its result arrives later as a ${MARKER_EXAMPLE} message. A child may wait on background work it started (timers, nested subagents) before it reports, and is stopped at its timeout.`,
    promptGuidelines: [
      "Use `subagent` for one task that can run alongside your own work, such as an independent review, a long scan, or a second opinion.",
      "Use `subagent` for several independent tasks in one turn, such as research in separate areas, a change read from several perspectives, or verification from several angles, so they finish sooner and disagreement surfaces.",
      "Do not use `subagent` for work your next step depends on, for a task one or two tool calls would answer, or for a task you cannot describe concretely; do those locally.",
      "Give `subagent` a self-contained prompt: it starts with no conversation, cannot ask questions or be resumed, and returns one answer capped at 16 KB, so state the files, the constraints, and the result you expect back, and ask for a file when it may write.",
      'For a fix you have already diagnosed, tell `subagent` the finding and the intended change; never write "fix what you find", which delegates the understanding instead of the work. Delegate verification of a concrete artifact; interpret an unclear finding yourself.',
      "Split write scopes before spawning: `subagent` children share this working tree and can edit it, with no isolation, so keep concurrent writers on disjoint files.",
      'Pass read-only `tools` such as ["read", "grep", "find"] to a research `subagent`, and give an editing child only the tools its change needs.',
      "For review and judging, especially code review, give `subagent` a different `model` from the one that produced the work when one is available, ideally from another family: a reviewer that shares the author's model shares its blind spots.",
      `After calling \`subagent\`, do non-overlapping work: do not poll, do not redo the task, and never predict or invent its result before the ${MARKER_EXAMPLE} message arrives.`,
      "Use `subagent_status` to answer whether a child still runs, not to poll, and `subagent_kill` to stop one whose result you no longer need.",
      `A child stays alive after its turns, so a timer or nested subagent it started can wake it; it reports by calling its own \`${FINISH_TOOL}\` tool. A child that never calls it keeps running until its \`timeoutSec\` passes, so raise that timeout when the child is meant to wait on long background work, and tell it to stop timers it no longer needs.`,
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
      if (!Number.isFinite(timeoutSec) || timeoutSec <= 0) {
        return toolText(
          "The subagent timeout must be a positive number of seconds.",
        );
      }
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
    description: `Report the subagents this session started: those still running, and the last ${FINISHED_HISTORY} that ended. Use it to check on a subagent instead of polling its result.`,
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
 * Warn the child once its timeout approaches, so it can wrap up by itself.
 *
 * The parent still enforces the deadline; this only gives a model that forgot
 * to finish, or that is waiting on slow background work, one last chance to
 * deliver a usable answer instead of being cut off. `triggerTurn` wakes a child
 * that is idle on a timer and `steer` reaches one that is mid-turn, which is
 * exactly the delivery this needs.
 *
 * @param pi - Extension API of the child process.
 * @param runner - Session state telling whether the child already finished.
 */
function warnBeforeDeadline(pi: ExtensionAPI, runner: SubagentRunner): void {
  const timeoutSec = Number(process.env[TIMEOUT_ENV]);
  if (!Number.isFinite(timeoutSec) || timeoutSec <= 0) return;

  const leadSec = Math.min(
    timeoutSec / 2,
    Math.max(MIN_WARN_LEAD_SEC, timeoutSec * (1 - WARN_AT)),
  );
  const warning = setTimeout(
    () => {
      // A child that already asked to finish needs no warning.
      if (runner.finishRequested()) return;
      pi.sendMessage(
        {
          customType: "subagent-deadline",
          content: `[subagent deadline] About ${Math.ceil(leadSec)}s of this session's ${timeoutSec}s budget is left. Wrap up now: finish what you can and call \`${FINISH_TOOL}\` with your best answer. Anything still pending is abandoned at the deadline, so start no background work that cannot finish in time.`,
          display: true,
        },
        { deliverAs: "steer", triggerTurn: true },
      );
    },
    (timeoutSec - leadSec) * 1000,
  );
  // The timer must not be the reason the child stays alive, and process exit
  // cancels it: no shutdown hook is needed for it.
  warning.unref();
}

/**
 * Build the `subagent_finish` tool, which only a spawned child registers.
 *
 * Its session outlives its turns so async tools can wake it, which means the
 * process needs an explicit end: this tool is the only thing that closes it.
 * The request is honored at the next settle, so the turn's own answer is
 * recorded before the session ends.
 *
 * The snippet and guidelines are this tool's whole purpose in prose: pi puts
 * them in the system prompt of every session that declares the tool, which is
 * exactly the spawned child. That includes the child's role, so nothing else
 * has to be appended to its system prompt.
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
      "End this subagent session and report your last message to the parent. Anything still pending is abandoned.",
    promptSnippet:
      "End this subagent session and report your last message; a turn ending does not end the session.",
    promptGuidelines: [
      "You are a subagent working alone in the current directory: no user can answer questions, so finish the task and report back concisely.",
      "This subagent session outlives its turns so background work you start, such as a timer or a nested subagent, can still wake you after you stop calling tools: end the turn instead of waiting for it in a loop, and react when its notification arrives.",
      `Call \`${FINISH_TOOL}\` when your answer is final, even if you started no background work: the session does not end when a turn does, so this call is what reports you to the parent.`,
      `Background work still pending when you call \`${FINISH_TOOL}\` is abandoned, so wait for anything you still need before finishing.`,
    ],
    parameters: FinishParams,
    async execute() {
      runner.requestFinish();
      return toolText(
        "Finishing: this session ends after this turn, and any background work still pending is abandoned.",
      );
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
      await ctx.ui.custom<void>((tui, theme, _kb, done) =>
        runner.createOverlay(tui, theme, () => done()),
      );
      runner.detachOverlay();
    },
  };
}

/**
 * End a spawned child when its model says the work is done.
 *
 * A child runs in RPC mode, so a turn with no tool calls no longer ends the
 * process: a timer or nested subagent that reports after that turn still wakes
 * it, which is the point. The flip side is that the process now has no natural
 * end, so the model ends it: `subagent_finish` sets the request, and the next
 * settle -- after the turn's own answer is recorded -- closes the session.
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
