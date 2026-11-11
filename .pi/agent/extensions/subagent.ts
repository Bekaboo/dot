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
} from "@earendil-works/pi-tui";
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

/** Braille frames pi's built-in working spinner uses. */
const SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

/** Spinner frame interval in ms, matching pi's built-in working indicator. */
const SPINNER_INTERVAL_MS = 80;

/** How much streaming text is kept for the overlay, in bytes. */
const LIVE_TEXT_CAP_BYTES = 4 * 1024;

/** Horizontal padding inside the `/subagents` overlay. */
const OVERLAY_PADDING_X = 2;

/** A subagent that has not finished yet, as `/subagents` shows it. */
interface RunningSubagent {
  id: string;
  /** Model as requested, empty when the child inherits pi's default. */
  model: string;
  /** Tools as requested, empty when the child gets pi's defaults. */
  tools: string[];
  cwd: string;
  startedAt: number;
  /** Creation order, so two children started in one millisecond stay ordered. */
  order: number;
  /** Latest assistant text the child emitted, empty before it speaks. */
  lastMessage: string;
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
  /** Creation order, so two children started in one millisecond stay ordered. */
  order: number;
  /** Last assistant text the child emitted. */
  lastMessage: string;
}

/** One line of the `/subagents` overlay. */
interface SubagentRow {
  id: string;
  /** `running`, or the terminal state of a finished child. */
  state: string;
  /** Creation order, so two children started in one millisecond stay ordered. */
  order: number;
  /** Elapsed seconds: live while running, at exit once finished. */
  seconds: number;
  model: string;
  tools: string[];
  cwd: string;
  /** Last assistant text the child emitted, or an empty string. */
  lastMessage: string;
}

/** How many finished children are remembered for `subagent_status`. */
const FINISHED_HISTORY = 10;

/** What the last assistant message of a child says, once its records are parsed. */
interface LastTurn {
  /** Answer text of that message, or an empty string. */
  answer: string;
  /** Text of the message currently streaming, by content-block index. */
  blocks: Map<number, string>;
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
    subagent: Omit<
      RunningSubagent,
      "startedAt" | "order" | "lastMessage" | "prompt"
    > & {
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
      order: this.nextOrder++,
      lastMessage: "",
    };
    this.running.set(running.id, running);
    this.refreshOverlay();

    const lastTurn: LastTurn = { answer: "", blocks: new Map() };
    let stderrTail = "";
    let finished = false;
    let stopped = false;

    const appendStderr = (text: string) => {
      stderrTail = truncateBytes(stderrTail + text, STDERR_CAP_BYTES);
    };
    // In JSON mode a malformed record is the only place a parser complaint can
    // go; it lands next to the child's own stderr.
    proc.stdout.setEncoding("utf8");
    proc.stdout.on(
      "data",
      recordParser(appendStderr, lastTurn, (text) => {
        running.lastMessage = text;
        this.refreshOverlay();
      }),
    );
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
        order: running.order,
        lastMessage: running.lastMessage,
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
        return `${marker(job.id)} running for ${seconds}s (${subagentSettings(job)})`;
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
      state: "running",
      order: job.order,
      seconds: elapsedSec(job.startedAt),
      model: job.model,
      tools: job.tools,
      cwd: job.cwd,
      lastMessage: job.lastMessage,
    }));
    const finished = this.finished.map((job) => ({
      id: job.id,
      state: job.state,
      order: job.order,
      seconds: job.seconds,
      model: job.model,
      tools: job.tools,
      cwd: job.cwd,
      lastMessage: job.lastMessage,
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
        state: "killed",
        model: job?.model ?? "",
        tools: job?.tools ?? [],
        cwd: job?.cwd ?? "",
        order: job?.order ?? 0,
        lastMessage: job?.lastMessage ?? "",
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
        content: `${marker(id)} ${outcome.status}\n${outcome.body}`,
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
 * render, so elapsed time and the last message stay current. A running child
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
   * Render every subagent on one line each.
   *
   * @param rows - Rows the overlay shows.
   * @param width - Overlay width, including the text padding.
   * @returns One width-truncated line per subagent.
   */
  private renderRows(rows: SubagentRow[], width: number): string {
    const inner = Math.max(0, width - OVERLAY_PADDING_X * 2);
    return rows
      .map((row) => truncateToWidth(this.renderRow(row), inner, "...", true))
      .join("\n");
  }

  /**
   * Render one subagent as spinner or state marker, settings and last message.
   *
   * @param row - Subagent to render.
   * @returns The styled line, before width truncation.
   */
  private renderRow(row: SubagentRow): string {
    const { theme } = this;
    const status =
      row.state === "running"
        ? `${row.seconds}s`
        : `${row.state} after ${row.seconds}s`;
    const head = [
      stateMarker(row.state, this.frame, theme),
      theme.bold(row.id),
      theme.fg("muted", status),
      theme.fg("dim", subagentSettings(row)),
    ].join(" ");
    const message = firstLine(row.lastMessage);
    return message ? `${head} ${theme.fg("muted", message)}` : head;
  }

  /** Start or stop the animation to match the rows. */
  private syncAnimation(): void {
    if (this.readRows().some((row) => row.state === "running")) {
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
 * Glyph and color for a subagent's state, with the spinner while it runs.
 *
 * @param state - `running` or the terminal state of a finished child.
 * @param frame - Current spinner frame index.
 * @param theme - Active theme.
 * @returns The styled marker.
 */
function stateMarker(state: string, frame: number, theme: Theme): string {
  switch (state) {
    case "running":
      return theme.fg("accent", SPINNER_FRAMES[frame % SPINNER_FRAMES.length]);
    case "done":
      return theme.fg("success", "✓");
    case "failed":
      return theme.fg("error", "✗");
    default:
      return theme.fg("dim", "·");
  }
}

/**
 * First non-blank line of a child's last message.
 *
 * @param text - Message text, possibly multi-line or empty.
 * @returns Its first non-blank line, trimmed, or an empty string.
 */
function firstLine(text: string): string {
  for (const line of text.split("\n")) {
    if (line.trim() !== "") return line.trim();
  }
  return "";
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
 * Read the latest assistant text out of one JSONL record.
 *
 * The stream is delta-only, so the authoritative content is the completed
 * `message_end.message`; a new answer replaces the previous one. Text blocks
 * are updated between completions, so the overlay can follow the child live.
 *
 * @param lastTurn - Last assistant message, updated in place.
 * @param record - Parsed `--mode json` record.
 * @param onText - Called with the visible text after each update.
 */
function absorbRecord(
  lastTurn: LastTurn,
  record: unknown,
  onText?: (text: string) => void,
): void {
  const event = record as JsonAgentSessionEvent;
  if (event.type === "message_update") {
    const update = event.assistantMessageEvent;
    if (update.type === "text_delta") {
      const text =
        (lastTurn.blocks.get(update.contentIndex) ?? "") + update.delta;
      lastTurn.blocks.set(
        update.contentIndex,
        truncateBytes(text, LIVE_TEXT_CAP_BYTES),
      );
      onText?.(draftText(lastTurn));
    }
    if (update.type === "text_end") {
      lastTurn.blocks.set(
        update.contentIndex,
        truncateBytes(update.content, LIVE_TEXT_CAP_BYTES),
      );
      onText?.(draftText(lastTurn));
    }
    return;
  }
  if (event.type === "message_start") {
    if (event.message.role === "assistant") lastTurn.blocks.clear();
    return;
  }
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
  lastTurn.blocks.clear();
  // A message with only tool calls has no text to show; keep the last words.
  if (lastTurn.answer) onText?.(lastTurn.answer);
}

/**
 * Join the text blocks of the message currently streaming.
 *
 * @param lastTurn - Last assistant message, holding the blocks.
 * @returns The visible draft text.
 */
function draftText(lastTurn: LastTurn): string {
  return [...lastTurn.blocks.entries()]
    .sort(([left], [right]) => left - right)
    .map(([, text]) => text)
    .join("\n");
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
 * @param onText - Called with the visible text after each update.
 * @returns A function that accepts output chunks.
 */
function recordParser(
  write: (text: string) => void,
  lastTurn: LastTurn,
  onText?: (text: string) => void,
) {
  let partial = "";
  let skipping = false;
  const absorb = (line: string) => {
    if (!line.trim()) return;
    try {
      absorbRecord(lastTurn, JSON.parse(line), onText);
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
      `Treat a ${MARKER_EXAMPLE} report as a claim to verify, not as proof the work is done.`,
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
 * Describe a child's model, tools and working directory on one line.
 *
 * @param job - Model, tools and working directory of the child.
 * @returns Text such as "qoder/Fast, tools=read,bash, /work".
 */
function subagentSettings(job: {
  model: string;
  tools: string[];
  cwd: string;
}): string {
  return [
    job.model || "model=default",
    job.tools.length > 0 ? `tools=${job.tools.join(",")}` : "tools=default",
    job.cwd,
  ].join(", ");
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
}
