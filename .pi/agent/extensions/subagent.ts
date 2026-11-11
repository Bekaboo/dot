/**
 * Subagent tool.
 *
 * `subagent()` spawns a separate `pi -p --mode json` process for a
 * self-contained task, returns as soon as the child is running, and injects a
 * `[subagent <id>]` message into this session when the child finishes. The
 * child gets a fresh context window; its prompt, tools, model and working
 * directory are chosen per call.
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
  ExtensionContext,
  JsonAgentSessionEvent,
  ToolDefinition,
} from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

/** Custom message type used for subagent notifications. */
const NOTICE_TYPE = "subagent";

/** How much of the child's final answer to put in a notification, in bytes. */
const OUTPUT_CAP_BYTES = 16 * 1024;

/** How much of the child's stderr to keep for a failure report, in bytes. */
const STDERR_CAP_BYTES = 2 * 1024;

/** Grace period before a child that ignored SIGTERM gets SIGKILL, in ms. */
const KILL_GRACE_MS = 2_000;

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

/** Longest single JSONL record kept from the child, in bytes. */
const MAX_RECORD_BYTES = 8 * 1024 * 1024;

/** Prefix for ids generated when the caller omits one. */
const AUTO_ID_PREFIX = "worker";

/** A subagent that has not finished yet, as `/subagents` shows it. */
interface RunningSubagent {
  id: string;
  /** Model as requested, empty when the child inherits pi's default. */
  model: string;
  /** Tools as requested, empty when the child gets pi's defaults. */
  tools: string[];
  cwd: string;
  startedAt: number;
}

/** A child that ended, kept briefly so `subagent_status` can report it. */
interface FinishedSubagent {
  id: string;
  /** Elapsed seconds at exit. */
  seconds: number;
  /** Outcome word: done, failed, killed, or cancelled by a reload. */
  state: string;
  /** Failure text, when the child did not finish cleanly. */
  reason?: string;
  model: string;
  tools: string[];
  cwd: string;
}

/** How many finished children are remembered for `subagent_status`. */
const FINISHED_HISTORY = 10;

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
  state: "done" | "failed";
  /** One-line summary, such as "finished in 12s.". */
  status: string;
  /** What the child said, or why it failed. */
  body: string;
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
  private nextId = 1;

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
   * @param id - Requested id, empty to auto-generate one.
   * @param cwd - Absolute working directory for the child.
   * @returns The id to use, or the problem to report to the agent.
   */
  reserveId(
    id: string | undefined,
    cwd: string,
  ): { id: string } | { problem: string } {
    const requested = id?.trim();
    if (requested === "")
      return { problem: "The subagent id must not be empty." };
    if (requested && this.running.has(requested)) {
      return { problem: `A subagent named "${requested}" is already running.` };
    }
    if (!fs.statSync(cwd, { throwIfNoEntry: false })?.isDirectory()) {
      return { problem: `Working directory is not a directory: ${cwd}` };
    }
    if (requested) return { id: requested };
    while (this.running.has(`${AUTO_ID_PREFIX}-${this.nextId}`)) this.nextId++;
    return { id: `${AUTO_ID_PREFIX}-${this.nextId++}` };
  }

  /**
   * Start the child and report its result when it exits.
   *
   * @param subagent - Id, model, thinking level, tools, working directory and
   *   prompt of the child.
   */
  start(
    subagent: Omit<RunningSubagent, "startedAt" | "prompt"> & {
      prompt: string;
      /** Thinking level to force, empty to keep the model's own setting. */
      thinking: string;
    },
  ): void {
    const { command, args } = childCommand(subagent);
    const proc = spawn(command, args, {
      cwd: subagent.cwd,
      shell: false,
      stdio: ["ignore", "pipe", "pipe"],
    });

    this.children.set(subagent.id, proc);
    const running: RunningSubagent = {
      id: subagent.id,
      model: subagent.model,
      tools: subagent.tools,
      cwd: subagent.cwd,
      startedAt: Date.now(),
    };
    this.running.set(running.id, running);

    const lastTurn: LastTurn = { answer: "" };
    let stderrTail = "";
    let finished = false;
    let stopped = false;

    const appendStderr = (text: string) => {
      stderrTail = truncateBytes(stderrTail + text, STDERR_CAP_BYTES);
    };
    // In JSON mode a malformed record is the only place a parser complaint can
    // go; it lands next to the child's own stderr.
    proc.stdout.setEncoding("utf8");
    proc.stdout.on("data", recordParser(appendStderr, lastTurn));
    proc.stderr.setEncoding("utf8");
    proc.stderr.on("data", appendStderr);

    // `error` and `close` can both fire for one child; report it only once.
    const finish = (failure: string | undefined) => {
      if (finished) return;
      finished = true;
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
      });
      this.deliver(running.id, outcome);
    };

    this.stoppers.set(running.id, () => {
      stopped = true;
      return stopProcess(proc);
    });

    proc.on("error", (error) => finish(`spawn error: ${error.message}`));
    proc.on("close", (code, signal) =>
      finish(failureOf(lastTurn, code, signal)),
    );
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
        return `${marker(job.id)} running for ${seconds}s${describe(job)}`;
      });
    const finished = this.finished
      .filter((job) => matches(job.id))
      .map(
        (job) =>
          `${marker(job.id)} ${job.state} after ${job.seconds}s${job.reason ? `: ${job.reason}` : ""}`,
      );
    const lines = [...running, ...finished];
    if (lines.length > 0) return lines.join("\n");
    return wanted.size === 0
      ? "No subagents have run in this session."
      : `No subagent named ${[...wanted].map(marker).join(", ")}.`;
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
        state: "killed",
        model: job?.model ?? "",
        tools: job?.tools ?? [],
        cwd: job?.cwd ?? "",
      });
      this.running.delete(id);
      this.stoppers.delete(id);
      waits.push(stop());
    }
    await Promise.all(waits);
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
        content: `${marker(id)} ${outcome.status}\n${outcome.body}`,
        display: true,
        details: { id, state: outcome.state },
      },
      { deliverAs: "steer", triggerTurn: true },
    );
  }
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

/** The marker as the model sees it in descriptions, before any id exists. */
const MARKER_EXAMPLE = marker("<id>");

/** Schema for the `subagent` tool. */
const SubagentParams = Type.Object({
  prompt: Type.String({
    description:
      "Full task for the subagent. It has no access to this conversation, so include every file path, constraint and deliverable it needs.",
  }),
  id: Type.Optional(
    Type.String({
      description:
        "Short, purpose-bearing name used in every notification, e.g. review-auth or scan-tests.",
    }),
  ),
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

/**
 * Read the last assistant message out of one JSONL record.
 *
 * The stream is delta-only, so the authoritative content is the completed
 * `message_end.message`; a new answer replaces the previous one.
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
 * Split child output into JSONL records and feed them to `absorbRecord`.
 *
 * Records are consumed as they arrive, so a long run retains only the latest
 * answer. An oversized record is skipped up to its next newline instead of
 * growing the buffer without bound.
 *
 * @param write - Sink for parser complaints, usually stderr accumulation.
 * @param lastTurn - Last assistant message, updated in place.
 * @returns A function that accepts output chunks.
 */
function recordParser(write: (text: string) => void, lastTurn: LastTurn) {
  let partial = "";
  let skipping = false;
  const absorb = (line: string) => {
    if (!line.trim()) return;
    try {
      absorbRecord(lastTurn, JSON.parse(line));
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
    state: "failed",
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
 * Build the invocation for the child pi process.
 *
 * @param subagent - Model, thinking level, tools, working directory and prompt
 *   of the child.
 * @returns Command and arguments to spawn.
 */
function childCommand(subagent: {
  model: string;
  thinking: string;
  tools: string[];
  cwd: string;
  prompt: string;
}): { command: string; args: string[] } {
  // Reuse the build that is already running, so a second pi on PATH cannot win.
  const command = process.env.PI_BIN ?? process.argv[1] ?? "pi";
  const args = ["-p", "--mode", "json", "--no-session"];
  if (subagent.model) args.push("--model", subagent.model);
  // Only set on the inherited path: `--thinking` outranks a `:level` suffix.
  if (subagent.thinking) args.push("--thinking", subagent.thinking);
  if (subagent.tools.length > 0) args.push("--tools", subagent.tools.join(","));
  args.push(
    "--append-system-prompt",
    `You are a subagent working in ${subagent.cwd}. Finish the task and report back concisely.`,
    // The leading "Task:" keeps pi from parsing the prompt as CLI syntax.
    `Task: ${subagent.prompt}`,
  );
  return { command, args };
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
    description: `Start a separate pi process with a fresh context to work on a task in the background. Returns immediately; the child's answer arrives later as a "${MARKER_EXAMPLE} ..." message.`,
    promptSnippet: `Spawn a background pi subagent with its own prompt, tools and model; its result arrives later as a ${MARKER_EXAMPLE} message.`,
    promptGuidelines: [
      "Use `subagent` to hand off self-contained work that can run alongside your own work, such as an independent review or a long scan.",
      "Give `subagent` a complete prompt: it cannot see this conversation.",
      `Do not poll for \`subagent\`'s result; keep working and its ${MARKER_EXAMPLE} message will arrive on its own.`,
    ],
    parameters: SubagentParams,
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const cwd = params.cwd ? path.resolve(ctx.cwd, params.cwd) : ctx.cwd;
      const reserved = runner.reserveId(params.id, cwd);
      if ("problem" in reserved) return toolText(reserved.problem);
      const { id } = reserved;

      const { prompt, tools = [], model = "" } = params;
      const selection = childSelection(model, ctx);
      runner.start({
        id,
        prompt,
        model: selection.model,
        thinking: selection.thinking,
        tools,
        cwd,
      });

      const config = [
        `model=${selection.model || "default"}`,
        `tools=${tools.length > 0 ? tools.join(",") : "default"}`,
        `cwd=${cwd}`,
      ].join(", ");
      return toolText(
        `Subagent "${id}" started (${config}). Its result arrives as a "${marker(id)}" message.`,
        { id, cwd, model: selection.model, tools },
      );
    },
  };
}

/**
 * Describe a subagent's non-obvious settings on one line.
 *
 * @param job - Model, tools and working directory of the child.
 * @returns Suffix such as " (qoder/Fast, tools=read,bash, /work)".
 */
function describe(job: {
  model: string;
  tools: string[];
  cwd: string;
}): string {
  const details = [
    job.model || "model=default",
    job.tools.length > 0 ? `tools=${job.tools.join(",")}` : "tools=default",
    job.cwd,
  ].join(", ");
  return ` (${details})`;
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
    description:
      "Report every subagent this session started: still running, or how it ended. Use it to check on a subagent instead of polling its result.",
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
 * Register the subagent tools, `/subagents`, and the shutdown hook.
 *
 * @param pi - Extension API.
 */
export default function subagent(pi: ExtensionAPI) {
  const runner = new SubagentRunner(pi);

  pi.registerTool(subagentTool(runner));
  pi.registerTool(statusTool(runner));
  pi.registerTool(killTool(runner));
  pi.registerCommand("subagents", {
    description: "List the subagents that are still running",
    handler: async (_args: string, ctx: ExtensionContext) => {
      ctx.ui.notify(runner.status(), "info");
    },
  });
  // Async so the handler's promise is awaited: pi waits for children to close.
  pi.on("session_shutdown", async (event) => {
    await runner.shutdown(event.reason);
  });
}
