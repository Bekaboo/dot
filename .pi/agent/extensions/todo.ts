/**
 * Todo Extension - a markdown-style checklist the agent plans with.
 *
 * Three tools keep one checklist per session branch. One action per tool keeps
 * each schema to the parameters that action actually uses:
 * - `todo_list`: view the list;
 * - `todo_write`: replace the whole list (initial plan or major rework);
 * - `todo_edit`: exact-text replacements applied by Pi's own edit tool, so a
 *   misremembered item fails to match instead of silently corrupting the list.
 *
 * Every result carries the full list, both for the model and as a snapshot in
 * `details`, so branches and forks restore the list they had at that point.
 *
 * Steering:
 * - After `REMIND_STALE_LIST_AFTER_TURNS` turns without a todo call or user
 *   input, while the list has unfinished items, a hint is appended to the
 *   next request only (not persisted in the transcript);
 * - After `REMIND_NEW_TASK_AFTER_TURNS` turns without a todo call or user
 *   input, a hint asks the agent to plan with the todo tools and is appended
 *   the same way. It only fires while the list is empty or fully closed, i.e.
 *   when a new task started; a stale list is left to the stale-list hint
 *   above. This catches long-horizon agents that never wrote a list, including
 *   small models that only reach for `bash`;
 * - When the agent stops with unfinished todo items, it will be reminded
 *   about them to either continue working for the target or mark the items
 *   cancelled.
 */

import type {
  AgentBeforeSettleEvent,
  AgentBeforeSettleEventResult,
  AgentToolResult,
  ContextEventResult,
  ContextWithSystemEvent,
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
  Theme,
  ToolDefinition,
  ToolExecutionEndEvent,
  TurnEndEvent,
  TurnEndEventResult,
} from "@earendil-works/pi-coding-agent";

import { createEditToolDefinition } from "@earendil-works/pi-coding-agent";

import {
  type Component,
  type KeyId,
  matchesKey,
  Text,
  type TUI,
} from "@earendil-works/pi-tui";
import { type Static, Type } from "typebox";

import { OverlayPage } from "./utils/overlay.ts";
import { scrolledStart } from "./utils/page.ts";

/** Turns of an unchanged checklist before the agent is nudged to update it. */
export const REMIND_STALE_LIST_AFTER_TURNS = 16;

/**
 * Turns of work without user input or todo calls before a new task, meaning an
 * empty or fully closed checklist, is asked for a plan.
 */
export const REMIND_NEW_TASK_AFTER_TURNS = 32;

const LIST_NAME = "todo-list";
const HINT_ENTRY_TYPE = "todo-hint";
const CONTINUE_MESSAGE_TYPE = "todo-continue";

/**
 * Tool names whose results snapshot the checklist.
 *
 * `todo` stays for backward compatibility: it is never registered, but branches
 * recorded before the split still restore their checklist from its results.
 */
const TODO_TOOLS = new Set(["todo_list", "todo_write", "todo_edit", "todo"]);

/** Checklist marker for each item status; the single source of truth. */
const MARKERS = {
  pending: " ",
  in_progress: "~",
  completed: "x",
  cancelled: "-",
} as const;

type TodoStatus = keyof typeof MARKERS;

/** Item status keyed by its checklist marker. */
const STATUS_BY_MARKER = new Map<string, TodoStatus>(
  Object.entries(MARKERS).map(([status, marker]) => [
    marker,
    status as TodoStatus,
  ]),
);

/** Bracketed markers as they appear in prompts and messages. */
const PENDING_BOX = box("pending");
const IN_PROGRESS_BOX = box("in_progress");
const COMPLETED_BOX = box("completed");
const CANCELLED_BOX = box("cancelled");

/** Regex character class matching any status marker. */
const MARKER_CLASS = Object.values(MARKERS)
  .map((marker) => marker.replace(/[\\\]^-]/g, "\\$&"))
  .join("");

/** One checklist line: `- [m] text`, where `m` is a status marker. */
const ITEM_PATTERN = new RegExp(`^- \\[([${MARKER_CLASS}])\\] (\\S.*)$`);

/** Accepted line formats, listed in error messages. */
const LINE_FORMATS = Object.keys(MARKERS)
  .map((status) => `"- ${box(status as TodoStatus)} text"`)
  .join(", ");

/** Schema for the `todo_list` tool. */
const TodoListParams = Type.Object({});

/** Schema for the `todo_write` tool. */
const TodoWriteParams = Type.Object({
  list: Type.String({
    description:
      "Complete Markdown checklist replacing the current one. Use for the initial plan or a major rework.",
  }),
});

const EditParams = Type.Object({
  oldText: Type.String({
    description: "Exact text of the current list to replace; must be unique.",
  }),
  newText: Type.String({ description: "Replacement text." }),
});

/** Schema for the `todo_edit` tool. */
const TodoEditParams = Type.Object({
  edits: Type.Array(EditParams, {
    description:
      "Exact-text replacements on the current list, same rules as the edit tool.",
  }),
});

/** Display color for each status marker. */
const STATUS_COLOR = {
  pending: "muted",
  in_progress: "accent",
  completed: "success",
  cancelled: "dim",
} as const;

/** One parsed checklist item. */
interface TodoItem {
  status: TodoStatus;
  text: string;
}

/** Snapshot stored in every tool result for rendering and session replay. */
interface TodoDetails {
  list: string;
  error?: string;
}

/** One exact-text replacement against the current checklist. */
type TodoEdit = Static<typeof EditParams>;

/**
 * Format the checkbox for a status, e.g. `[x]`.
 *
 * @param status - Item status.
 * @returns The bracketed marker.
 */
function box(status: TodoStatus): string {
  return `[${MARKERS[status]}]`;
}

/**
 * Read the message of an unknown thrown value.
 *
 * @param error - Value thrown by validation or the edit tool.
 * @returns The message text.
 */
function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * Parse a checklist.
 *
 * @param list - Normalized checklist text.
 * @returns Parsed items in list order.
 */
function parseList(list: string): TodoItem[] {
  if (!list) return [];
  return list.split("\n").map((line) => {
    const match = ITEM_PATTERN.exec(line);
    if (!match) throw new Error(`Invalid todo line: "${line}"`);
    const status = STATUS_BY_MARKER.get(match[1]);
    if (!status) throw new Error(`Unknown todo marker: "${match[1]}"`);
    return { status, text: match[2] };
  });
}

/**
 * Normalize and validate a checklist before it becomes the current list.
 *
 * Blank lines are dropped so deleting an item cannot leave gaps behind.
 *
 * @param text - Candidate checklist text.
 * @returns The normalized checklist.
 * @throws When a line is not a checklist item.
 */
function normalizeList(text: string): string {
  const lines = text
    .split("\n")
    .map((line) => line.trimEnd())
    .filter((line) => line.trim() !== "");
  for (const line of lines) {
    if (!ITEM_PATTERN.test(line)) {
      throw new Error(
        `Invalid todo line: "${line}". Each line must be one of ${LINE_FORMATS}.`,
      );
    }
  }
  return lines.join("\n");
}

/**
 * Check whether the list still has work left.
 *
 * @param list - Current checklist.
 * @returns True when an item is pending or in progress.
 */
function hasUnfinished(list: string): boolean {
  return parseList(list).some(
    (item) => item.status === "pending" || item.status === "in_progress",
  );
}

/**
 * Format the list for the model.
 *
 * @param list - Current checklist.
 * @returns The checklist, or a note that it is empty.
 */
function describeList(list: string): string {
  return list ? `Current todo list:\n\n${list}` : "The todo list is empty.";
}

/**
 * Apply exact-text edits with Pi's edit tool against an in-memory list.
 *
 * Reusing the edit tool keeps its matching rules and error messages: missing,
 * duplicate, overlapping and no-op edits all fail the same way they do for
 * files, which is what the model already knows how to fix.
 *
 * @param list - Current checklist.
 * @param edits - Replacements to apply.
 * @param signal - Cancellation signal for the delegated edit.
 * @returns The edited checklist text, not yet validated.
 */
async function applyEdits(
  list: string,
  edits: TodoEdit[],
  signal?: AbortSignal,
): Promise<string> {
  // Edit a newline-terminated copy so deleting the last line with its "\n"
  // matches like any other line; normalizeList() drops the blank lines.
  let content = list ? `${list}\n` : "";
  const editTool = createEditToolDefinition("/", {
    operations: {
      access: async () => {},
      readFile: async () => Buffer.from(content),
      writeFile: async (_path, next) => {
        content = next;
      },
    },
  });
  await editTool.execute(
    "todo_edit",
    { path: LIST_NAME, edits },
    signal,
    undefined,
    undefined as never,
  );
  return content;
}

/**
 * Build a tool result carrying the full list.
 *
 * @param list - Checklist after the call.
 * @param message - Leading sentence for the model.
 * @param error - Error message when the call failed.
 * @returns A tool result whose details snapshot the list.
 */
function todoResult(
  list: string,
  message: string,
  error?: string,
): AgentToolResult<TodoDetails> {
  const text = `${error ? `Error: ${error}` : message}\n\n${describeList(list)}`;
  return {
    content: [{ type: "text", text }],
    details: error ? { list, error } : { list },
    ...(error ? { isError: true } : {}),
  };
}

/**
 * Choose the reminder for an agent that has gone quiet on its todo list.
 *
 * @param list - Current checklist.
 * @returns Reminder text, or undefined when there is no unfinished item.
 */
function staleListHint(list: string): string | undefined {
  if (!hasUnfinished(list)) return undefined;
  return [
    `<todo-reminder>`,
    `The todo list has not been viewed or updated recently.`,
    ``,
    list,
    ``,
    `If progress changed, update it with todo_edit: mark the current item ${IN_PROGRESS_BOX}, finished items ${COMPLETED_BOX}, abandoned items ${CANCELLED_BOX}. Ignore this if the list is accurate.`,
    `</todo-reminder>`,
  ].join("\n");
}

/**
 * Build the reminder for a long run whose checklist does not cover the work.
 *
 * Long-horizon agents, especially small models that reach only for `bash`,
 * keep their plan in the transcript instead of the list. Naming the tools and
 * their markers is what makes them adopt the checklist.
 *
 * @param list - Current checklist, empty or fully closed.
 * @returns Reminder text asking for the checklist to be adopted.
 */
function newTaskHint(list: string): string {
  return [
    `<todo-reminder>`,
    `You have worked ${REMIND_NEW_TASK_AFTER_TURNS} turns without user input, which usually means a long-horizon task. Plan and track it with the todo tools instead of keeping progress in your head:`,
    `- todo_write records the remaining work as a checklist;`,
    `- todo_edit marks the current item ${IN_PROGRESS_BOX} when you start it and ${COMPLETED_BOX} right after finishing it, before starting the next one.`,
    ``,
    describeList(list),
    `</todo-reminder>`,
  ].join("\n");
}

/**
 * Build the message that pushes a stopped agent with unfinished items.
 *
 * @param list - Current checklist.
 * @returns Message text that also offers legitimate ways to stop.
 */
function continueMessage(list: string): string {
  return [
    `You stopped, but the todo list still has unfinished items:`,
    ``,
    list,
    ``,
    `Continue with the next item if it is actionable now.`,
    `If you are waiting for the user's answer, say so briefly and stop.`,
    `If remaining items are blocked or no longer relevant, mark them ${CANCELLED_BOX} with todo_edit, then stop.`,
  ].join("\n");
}

/**
 * Append a reminder to the last tool result of an outgoing request.
 *
 * Attaching to the tool result keeps message roles unchanged. When the last
 * message is not a tool result, new input has arrived and the reminder is
 * dropped.
 *
 * @param messages - Full outgoing transcript.
 * @param hint - Reminder text.
 * @returns The transcript with the reminder attached, or undefined.
 */
function withHint(
  messages: ContextWithSystemEvent["messages"],
  hint: string,
): ContextWithSystemEvent["messages"] | undefined {
  const last = messages.at(-1);
  if (last?.role !== "toolResult") return undefined;
  const patched = {
    ...last,
    content: [...last.content, { type: "text" as const, text: hint }],
  };
  return [...messages.slice(0, -1), patched];
}

/**
 * Render checklist items.
 *
 * @param list - Checklist to render.
 * @param theme - Active theme.
 * @returns One colored line per item.
 */
function renderItems(list: string, theme: Theme): string[] {
  return parseList(list).map((item) => {
    const text =
      item.status === "completed" || item.status === "cancelled"
        ? theme.fg("dim", item.text)
        : theme.fg("text", item.text);
    return `${theme.fg(STATUS_COLOR[item.status], box(item.status))} ${text}`;
  });
}

/**
 * Count non-blank lines in a candidate checklist.
 *
 * @param list - Candidate checklist text.
 * @returns Number of checklist lines, ignoring blanks.
 */
function countItems(list: string): number {
  return list.split("\n").filter((line) => line.trim() !== "").length;
}

/**
 * Build the header line of a todo tool call.
 *
 * @param name - Tool name, e.g. `todo_edit`.
 * @param detail - Muted suffix describing the call, e.g. ` (2 edits)`.
 * @param theme - Active theme.
 * @returns The rendered header text.
 */
function callHeader(name: string, detail: string, theme: Theme): Text {
  return new Text(
    theme.fg("toolTitle", theme.bold(name)) + theme.fg("muted", detail),
    0,
    0,
  );
}

/**
 * Render a todo tool result as a colored checklist.
 *
 * @param result - Tool result from any todo tool.
 * @param theme - Active theme.
 * @returns The checklist, or Pi's error text when there is no snapshot.
 */
function renderTodoResult(
  result: AgentToolResult<TodoDetails>,
  theme: Theme,
): Text {
  const details = result.details;
  // Host validation and blocked-call errors have no checklist snapshot.
  if (typeof details?.list !== "string") {
    const text = result.content
      .filter((block) => block.type === "text")
      .map((block) => block.text)
      .join("\n");
    return new Text(theme.fg("error", text), 0, 0);
  }
  const lines = details.list
    ? renderItems(details.list, theme)
    : [theme.fg("dim", "No todos")];
  if (details.error) {
    lines.unshift(theme.fg("error", `Error: ${details.error}`));
  }
  return new Text(lines.join("\n"), 0, 0);
}

/**
 * Build the overlay for the `/todos` command.
 *
 * Built on the shared overlay page, like the subagent and timer overlays: a
 * bordered box with a title, a summary, one line per item and an Escape hint.
 * The items are cut to the rows the terminal leaves and scroll with the list
 * keys, so a short terminal keeps the hint visible and no item becomes
 * unreachable.
 *
 * @param tui - TUI the overlay renders into.
 * @param list - Checklist to display.
 * @param theme - Active theme.
 * @param close - Closes the overlay.
 * @returns An overlay component that closes on Escape or Ctrl+C.
 */
function createTodoOverlay(
  tui: TUI,
  list: string,
  theme: Theme,
  close: () => void,
): Component {
  const items = parseList(list);
  const closed = items.filter(
    (item) => item.status === "completed" || item.status === "cancelled",
  ).length;
  const summary = items.length
    ? theme.fg("muted", `${closed}/${items.length} closed`)
    : theme.fg("dim", "No todos yet. Ask the agent to add some!");
  const rendered = renderItems(list, theme);
  const hint = "Press Escape to close";
  const page = new OverlayPage(tui, theme, "Todos");
  page.setSummary(summary);
  /** First item the window shows. */
  let start = 0;

  return {
    render(width) {
      const capacity = page.measure(width, hint);
      start = scrolledStart(start, 0, rendered.length, capacity);
      page.setWindow(rendered, start, capacity, hint, width);
      return page.render(width);
    },
    invalidate: () => page.invalidate(),
    handleInput(data) {
      if (matchesKey(data, "escape") || matchesKey(data, "ctrl+c")) {
        close();
        return;
      }
      const pageRows = Math.max(1, page.rowCapacity);
      const moves: [KeyId, number][] = [
        ["up", -1],
        ["down", 1],
        ["pageUp", -pageRows],
        ["pageDown", pageRows],
      ];
      for (const [key, lines] of moves) {
        if (!matchesKey(data, key)) continue;
        start = scrolledStart(start, lines, rendered.length, pageRows);
        tui.requestRender();
        return;
      }
    },
  };
}

/**
 * Steering: show a recorded reminder in the transcript.
 *
 * Pi does not pad custom entries, so the line applies the transcript's
 * `outputPad` setting itself to align with messages and tool output.
 *
 * @param padding - Transcript output padding.
 * @param theme - Active theme.
 * @returns A one-line marker.
 */
function renderHintEntry(padding: number, theme: Theme): Text {
  return new Text(
    theme.fg("dim", "Todo reminder sent to the agent"),
    padding,
    0,
  );
}

/** Checklist and steering state owned by one extension instance. */
class Todo {
  /** Markdown checklist currently shown to the model. */
  private items = "";
  /** Turns since the last todo call, user input, or stale-list reminder. */
  private staleListTurns = 0;
  /** Turns since the last todo call, user input, or new-task reminder. */
  private newTaskTurns = 0;
  /** Whether a todo call finished during the current turn. */
  private touchedThisTurn = false;
  /** Reminder waiting to be appended to the next request. */
  private pendingHint?: string;
  /** Whether a stopped agent was pushed since the last user input. */
  private pushedSinceInput = false;
  /** Whether any tool ran since the last user input. */
  private workedSinceInput = false;

  /** Current checklist text, as the tools and the overlay show it. */
  get list(): string {
    return this.items;
  }

  /**
   * Show the current checklist.
   *
   * @returns A result with the full list.
   */
  async view(): Promise<AgentToolResult<TodoDetails>> {
    return todoResult(this.items, "Viewed the todo list.");
  }

  /**
   * Replace the whole checklist.
   *
   * @param text - Candidate checklist text.
   * @param signal - Cancellation signal; an aborted call leaves the list unchanged.
   * @returns A result with the full list; an invalid checklist keeps the old one.
   */
  async write(
    text: string,
    signal?: AbortSignal,
  ): Promise<AgentToolResult<TodoDetails>> {
    signal?.throwIfAborted();
    return this.commit(text);
  }

  /**
   * Apply exact-text replacements to the checklist.
   *
   * @param edits - Replacements to apply.
   * @param signal - Cancellation signal; an aborted call leaves the list unchanged.
   * @returns A result with the full list; a failed edit keeps the old one.
   */
  async edit(
    edits: TodoEdit[],
    signal?: AbortSignal,
  ): Promise<AgentToolResult<TodoDetails>> {
    signal?.throwIfAborted();
    let next: string;
    try {
      next = await applyEdits(this.items, edits, signal);
    } catch (error) {
      signal?.throwIfAborted();
      return todoResult(this.items, "", errorMessage(error));
    }
    return this.commit(next);
  }

  /**
   * Validate a candidate checklist and make it the current list.
   *
   * @param next - Candidate checklist, not yet normalized.
   * @returns A result with the full list; an invalid checklist keeps the old one.
   */
  private commit(next: string): AgentToolResult<TodoDetails> {
    try {
      this.items = normalizeList(next);
    } catch (error) {
      return todoResult(this.items, "", errorMessage(error));
    }
    return todoResult(this.items, "Updated the todo list.");
  }

  /**
   * Rebuild the list from the active session branch.
   *
   * The latest todo result on the branch wins, so forks and branches see the
   * list that existed at that point in history.
   *
   * @param ctx - Session context providing the active branch.
   */
  restore(ctx: ExtensionContext): void {
    this.items = "";
    this.resetSteering();

    for (const entry of ctx.sessionManager.getBranch()) {
      if (entry.type !== "message") continue;
      const message = entry.message;
      if (message.role !== "toolResult" || !TODO_TOOLS.has(message.toolName))
        continue;
      const details = message.details as TodoDetails | undefined;
      if (typeof details?.list !== "string") continue;
      this.items = details.list;
    }
  }

  /** Reset the steering state after user input or a session change. */
  resetSteering(): void {
    this.staleListTurns = 0;
    this.newTaskTurns = 0;
    this.touchedThisTurn = false;
    this.pendingHint = undefined;
    this.pushedSinceInput = false;
    this.workedSinceInput = false;
  }

  /**
   * Steering: track tool work and todo calls for the turn counters and push.
   *
   * @param event - Finished tool execution.
   */
  trackToolExecution(event: ToolExecutionEndEvent): void {
    this.workedSinceInput = true;
    if (TODO_TOOLS.has(event.toolName)) this.touchedThisTurn = true;
  }

  /**
   * Steering: count turns and queue a reminder once a window is hit.
   *
   * A checklist with work left is nudged every
   * `REMIND_STALE_LIST_AFTER_TURNS` turns. Once a run goes
   * `REMIND_NEW_TASK_AFTER_TURNS` turns without the user or the checklist, a
   * list that is empty or fully closed means a new task started, and the
   * agent is asked to plan it with the todo tools. Stale-list nudges do not
   * restart that window; only its own reminder does. Stalled turns count
   * towards both windows but never carry a reminder, which waits for the next
   * turn with a tool result.
   *
   * @param event - Turn boundary with the entries proposed so far.
   * @returns A transcript record of the reminder, or nothing.
   */
  countTurn(event: TurnEndEvent): TurnEndEventResult | undefined {
    if (this.touchedThisTurn) {
      this.touchedThisTurn = false;
      this.staleListTurns = 0;
      this.newTaskTurns = 0;
    } else {
      this.staleListTurns += 1;
      this.newTaskTurns += 1;
    }
    // A stalled turn (not completed, or no tool result) still counts as a
    // turn without the user, but it carries no tool result, so the reminder
    // waits for the next turn that does.
    if (event.outcome !== "completed" || event.toolResults.length === 0) {
      return undefined;
    }

    const freshTask = !hasUnfinished(this.items);
    const remindNewTask =
      freshTask && this.newTaskTurns >= REMIND_NEW_TASK_AFTER_TURNS;
    if (!remindNewTask && this.staleListTurns < REMIND_STALE_LIST_AFTER_TURNS) {
      return undefined;
    }

    const hint = remindNewTask
      ? newTaskHint(this.items)
      : staleListHint(this.items);
    this.staleListTurns = 0;
    if (!hint) return undefined;

    // Keep the new-task window armed across stale-list nudges: only its own
    // reminder restarts it.
    if (remindNewTask) this.newTaskTurns = 0;
    this.pendingHint = hint;
    // Recorded for the transcript only; custom entries never reach the model.
    return {
      entries: [
        ...event.entries,
        { type: "custom", customType: HINT_ENTRY_TYPE, data: { hint } },
      ],
    };
  }

  /**
   * Steering: attach the queued reminder to the next request only.
   *
   * @param event - Full outgoing transcript.
   * @returns The patched transcript, or nothing to keep it unchanged.
   */
  injectHint(event: ContextWithSystemEvent): ContextEventResult | undefined {
    const hint = this.pendingHint;
    if (!hint) return undefined;
    this.pendingHint = undefined;
    const messages = withHint(event.messages, hint);
    return messages ? { messages } : undefined;
  }

  /**
   * Steering: push an agent that stops with unfinished items, once per input.
   *
   * @param event - Final boundary before the agent settles.
   * @returns A continue request with a visible message, or nothing.
   */
  pushUnfinished(
    event: AgentBeforeSettleEvent,
  ): AgentBeforeSettleEventResult | undefined {
    if (event.outcome !== "completed" || this.pushedSinceInput) {
      return undefined;
    }
    // A reply without any tool call is discussion, not abandoned work.
    if (!this.workedSinceInput || !hasUnfinished(this.items)) {
      return undefined;
    }
    this.pushedSinceInput = true;
    return {
      entries: [
        ...event.entries,
        {
          type: "custom_message",
          customType: CONTINUE_MESSAGE_TYPE,
          content: continueMessage(this.items),
          display: true,
        },
      ],
      continue: true,
    };
  }
}

/**
 * Build the `todo_list` tool definition.
 *
 * @param todo - Session list state the tool reads.
 * @returns Tool definition registered with Pi.
 */
function todoListTool(
  todo: Todo,
): ToolDefinition<typeof TodoListParams, TodoDetails> {
  return {
    name: "todo_list",
    label: "Todo List",
    description:
      "Show the session todo list, a Markdown checklist. Every other todo tool also returns the full list, so call this only to re-read the current state.",
    promptSnippet: "View the session todo checklist",
    parameters: TodoListParams,
    // The todo tools share one mutable list, so Pi must run them in order.
    executionMode: "sequential",
    execute: () => todo.view(),

    renderCall(_args, theme) {
      return callHeader("todo_list", "", theme);
    },

    renderResult(result, _options, theme) {
      return renderTodoResult(result, theme);
    },
  };
}

/**
 * Build the `todo_write` tool definition.
 *
 * @param todo - Session list state the tool replaces.
 * @returns Tool definition registered with Pi.
 */
function todoWriteTool(
  todo: Todo,
): ToolDefinition<typeof TodoWriteParams, TodoDetails> {
  return {
    name: "todo_write",
    label: "Todo Write",
    description: `Replace the session todo list, a Markdown checklist. Item markers: \`- ${PENDING_BOX}\` pending, \`- ${IN_PROGRESS_BOX}\` in progress, \`- ${COMPLETED_BOX}\` done, \`- ${CANCELLED_BOX}\` cancelled. Use for the initial plan or a major rework. Returns the full list.`,
    promptSnippet: "Replace the session todo checklist with a new plan",
    promptGuidelines: [
      "Use `todo_write` to plan before multi-step work whose progress is worth tracking (e.g. review then fix findings, multi-file changes, fix-test-commit loops), or when the user lists several items. Skip it for single-step or purely conversational requests.",
    ],
    parameters: TodoWriteParams,
    // The todo tools share one mutable list, so Pi must run them in order.
    executionMode: "sequential",
    execute: (_toolCallId, params, signal) => todo.write(params.list, signal),

    renderCall(args, theme) {
      const count = countItems(args.list ?? "");
      return callHeader(
        "todo_write",
        ` (${count} item${count === 1 ? "" : "s"})`,
        theme,
      );
    },

    renderResult(result, _options, theme) {
      return renderTodoResult(result, theme);
    },
  };
}

/**
 * Build the `todo_edit` tool definition.
 *
 * @param todo - Session list state the tool edits.
 * @returns Tool definition registered with Pi.
 */
function todoEditTool(
  todo: Todo,
): ToolDefinition<typeof TodoEditParams, TodoDetails> {
  const editTool = createEditToolDefinition("/");
  return {
    name: "todo_edit",
    label: "Todo Edit",
    description: `Update the session todo list, a Markdown checklist, with exact-text replacements like the edit tool: each oldText must match the current list exactly and uniquely, otherwise nothing changes. Item markers: \`- ${PENDING_BOX}\` pending, \`- ${IN_PROGRESS_BOX}\` in progress, \`- ${COMPLETED_BOX}\` done, \`- ${CANCELLED_BOX}\` cancelled. Returns the full list.`,
    promptSnippet: "Edit the session todo checklist in place",
    promptGuidelines: [
      `Use \`todo_edit\` to mark an item ${IN_PROGRESS_BOX} when starting it and ${COMPLETED_BOX} right after finishing it, before starting the next one.`,
      `Use \`todo_edit\` when requirements change mid-task: update the list first, and mark abandoned items ${CANCELLED_BOX} instead of deleting them.`,
    ],
    parameters: TodoEditParams,
    // The todo tools share one mutable list, so Pi must run them in order.
    executionMode: "sequential",
    prepareArguments: editTool.prepareArguments as (
      args: unknown,
    ) => Static<typeof TodoEditParams>,
    execute: (_toolCallId, params, signal) => todo.edit(params.edits, signal),

    renderCall(args, theme) {
      const count = args.edits?.length ?? 0;
      return callHeader(
        "todo_edit",
        ` (${count} edit${count === 1 ? "" : "s"})`,
        theme,
      );
    },

    renderResult(result, _options, theme) {
      return renderTodoResult(result, theme);
    },
  };
}

/**
 * Build the `/todos` command.
 *
 * @param todo - Session list state the overlay shows.
 * @returns Command definition registered with Pi.
 */
function todosCommand(todo: Todo) {
  return {
    description: "Show the todo list on the current branch",
    handler: async (_args: string, ctx: ExtensionCommandContext) => {
      if (ctx.mode !== "tui") {
        ctx.ui.notify("/todos requires interactive mode", "error");
        return;
      }
      await ctx.ui.custom<void>((tui, theme, _kb, done) =>
        createTodoOverlay(tui, todo.list, theme, () => done()),
      );
    },
  };
}

/**
 * Register the todo extension with Pi.
 *
 * @param pi - Extension API used to register tools, commands and handlers.
 */
export default function todoExtension(pi: ExtensionAPI): void {
  const todo = new Todo();

  pi.registerTool(todoListTool(todo));
  pi.registerTool(todoWriteTool(todo));
  pi.registerTool(todoEditTool(todo));
  pi.registerCommand("todos", todosCommand(todo));
  pi.on("session_start", (_event, ctx) => todo.restore(ctx));
  pi.on("session_tree", (_event, ctx) => todo.restore(ctx));
  pi.on("input", () => todo.resetSteering());
  pi.on("tool_execution_end", (event) => todo.trackToolExecution(event));
  pi.on("turn_end", (event) => todo.countTurn(event));
  pi.on("context_with_system", (event) => todo.injectHint(event));
  pi.on("agent_before_settle", (event) => todo.pushUnfinished(event));
  pi.registerEntryRenderer(HINT_ENTRY_TYPE, (_entry, _options, theme) =>
    renderHintEntry(pi.getSettings().outputPad ?? 1, theme),
  );
}
