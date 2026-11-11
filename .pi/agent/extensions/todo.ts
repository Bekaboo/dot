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
 * - After `STEER_AFTER_TURNS` turns without a todo call or user input, while
 *   the list has unfinished items, a hint is appended to the next request
 *   only (not persisted in the transcript). Agents that never wrote a list
 *   are left alone;
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

import {
  createEditToolDefinition,
  DynamicBorder,
} from "@earendil-works/pi-coding-agent";

import {
  type Component,
  Container,
  matchesKey,
  Spacer,
  Text,
} from "@earendil-works/pi-tui";

import { type Static, Type } from "typebox";

const STEER_AFTER_TURNS = 16;
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

/**
 * Format the checkbox for a status, e.g. `[x]`.
 *
 * @param status - Item status.
 * @returns The bracketed marker.
 */
function box(status: TodoStatus): string {
  return `[${MARKERS[status]}]`;
}

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

/** One exact-text replacement against the current checklist. */
type TodoEdit = Static<typeof EditParams>;

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
 * @throws When a line is not a checklist item or several items are in progress.
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
  const list = lines.join("\n");
  const inProgress = parseList(list).filter(
    (item) => item.status === "in_progress",
  ).length;
  if (inProgress > 1) {
    throw new Error(
      `${inProgress} items are marked ${IN_PROGRESS_BOX}; at most one item can be in progress.`,
    );
  }
  return list;
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
  return list ? `Current todo list:\n${list}` : "The todo list is empty.";
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
function idleHint(list: string): string | undefined {
  if (!hasUnfinished(list)) return undefined;
  return [
    `<todo-reminder>`,
    `The todo list has not been viewed or updated recently.`,
    list,
    `If progress changed, update it with todo_edit: mark the current item ${IN_PROGRESS_BOX}, finished items ${COMPLETED_BOX}, abandoned items ${CANCELLED_BOX}. Ignore this if the list is accurate.`,
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
    list,
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

/** Display color for each status marker. */
const STATUS_COLOR = {
  pending: "muted",
  in_progress: "accent",
  completed: "success",
  cancelled: "dim",
} as const;

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
 * @param list - Checklist to display.
 * @param theme - Active theme.
 * @param close - Closes the overlay.
 * @returns An overlay component that closes on Escape or Ctrl+C.
 */
function createTodoOverlay(
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

  const container = new Container();
  container.addChild(
    new DynamicBorder((text) => theme.fg("borderMuted", text)),
  );
  container.addChild(new Text(theme.fg("accent", theme.bold("Todos")), 2, 1));
  container.addChild(new Text(summary, 2, 0));
  if (items.length) {
    container.addChild(new Spacer(1));
    container.addChild(new Text(renderItems(list, theme).join("\n"), 2, 0));
  }
  container.addChild(new Text(theme.fg("dim", "Press Escape to close"), 2, 1));
  container.addChild(
    new DynamicBorder((text) => theme.fg("borderMuted", text)),
  );

  return {
    render: (width) => container.render(width),
    invalidate: () => container.invalidate(),
    handleInput: (data) => {
      if (matchesKey(data, "escape") || matchesKey(data, "ctrl+c")) close();
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
  private list = "";
  /** Turns since the last todo call, user input, or reminder. */
  private idleTurns = 0;
  /** Whether a todo call finished during the current turn. */
  private touchedThisTurn = false;
  /** Reminder waiting to be appended to the next request. */
  private pendingHint?: string;
  /** Whether a stopped agent was pushed since the last user input. */
  private pushedSinceInput = false;
  /** Whether any tool ran since the last user input. */
  private workedSinceInput = false;

  /**
   * Show the current checklist.
   *
   * @returns A result with the full list.
   */
  async view(): Promise<AgentToolResult<TodoDetails>> {
    return todoResult(this.list, "Viewed the todo list.");
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
      next = await applyEdits(this.list, edits, signal);
    } catch (error) {
      signal?.throwIfAborted();
      return todoResult(this.list, "", errorMessage(error));
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
      this.list = normalizeList(next);
    } catch (error) {
      return todoResult(this.list, "", errorMessage(error));
    }
    return todoResult(this.list, "Updated the todo list.");
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
    this.list = "";
    this.resetSteering();

    for (const entry of ctx.sessionManager.getBranch()) {
      if (entry.type !== "message") continue;
      const message = entry.message;
      if (
        message.role !== "toolResult" ||
        !TODO_TOOLS.has(message.toolName)
      )
        continue;
      const details = message.details as TodoDetails | undefined;
      if (typeof details?.list !== "string") continue;
      this.list = details.list;
    }
  }

  /** Reset the steering state after user input or a session change. */
  resetSteering(): void {
    this.idleTurns = 0;
    this.touchedThisTurn = false;
    this.pendingHint = undefined;
    this.pushedSinceInput = false;
    this.workedSinceInput = false;
  }

  /**
   * Build the `todo_list` tool definition.
   *
   * @returns Tool definition registered with Pi.
   */
  createListTool(): ToolDefinition<typeof TodoListParams, TodoDetails> {
    return {
      name: "todo_list",
      label: "Todo List",
      description:
        "Show the session todo list, a Markdown checklist. Every other todo tool also returns the full list, so call this only to re-read the current state.",
      promptSnippet: "View the session todo checklist",
      parameters: TodoListParams,
      // The todo tools share one mutable list, so Pi must run them in order.
      executionMode: "sequential",
      execute: () => this.view(),

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
   * @returns Tool definition registered with Pi.
   */
  createWriteTool(): ToolDefinition<typeof TodoWriteParams, TodoDetails> {
    return {
      name: "todo_write",
      label: "Todo Write",
      description: `Replace the session todo list, a Markdown checklist. Item markers: \`- ${PENDING_BOX}\` pending, \`- ${IN_PROGRESS_BOX}\` in progress (at most one), \`- ${COMPLETED_BOX}\` done, \`- ${CANCELLED_BOX}\` cancelled. Use for the initial plan or a major rework. Returns the full list.`,
      promptSnippet: "Replace the session todo checklist with a new plan",
      promptGuidelines: [
        "Use todo_write to plan before multi-step work whose progress is worth tracking (e.g. review then fix findings, multi-file changes, fix-test-commit loops), or when the user lists several items. Skip it for single-step or purely conversational requests.",
      ],
      parameters: TodoWriteParams,
      // The todo tools share one mutable list, so Pi must run them in order.
      executionMode: "sequential",
      execute: (_toolCallId, params, signal) =>
        this.write(params.list, signal),

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
   * @returns Tool definition registered with Pi.
   */
  createEditTool(): ToolDefinition<typeof TodoEditParams, TodoDetails> {
    const editTool = createEditToolDefinition("/");
    return {
      name: "todo_edit",
      label: "Todo Edit",
      description: `Update the session todo list, a Markdown checklist, with exact-text replacements like the edit tool: each oldText must match the current list exactly and uniquely, otherwise nothing changes. Item markers: \`- ${PENDING_BOX}\` pending, \`- ${IN_PROGRESS_BOX}\` in progress (at most one), \`- ${COMPLETED_BOX}\` done, \`- ${CANCELLED_BOX}\` cancelled. Returns the full list.`,
      promptSnippet: "Edit the session todo checklist in place",
      promptGuidelines: [
        `Use todo_edit to mark an item ${IN_PROGRESS_BOX} when starting it and ${COMPLETED_BOX} right after finishing it, before starting the next one. Keep at most one item ${IN_PROGRESS_BOX}.`,
        `When requirements change mid-task, update the todo list first. Mark abandoned items ${CANCELLED_BOX} instead of deleting them.`,
      ],
      parameters: TodoEditParams,
      // The todo tools share one mutable list, so Pi must run them in order.
      executionMode: "sequential",
      prepareArguments: editTool.prepareArguments as (
        args: unknown,
      ) => Static<typeof TodoEditParams>,
      execute: (_toolCallId, params, signal) =>
        this.edit(params.edits, signal),

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
   * @returns Command definition registered with Pi.
   */
  createCommand() {
    return {
      description: "Show the todo list on the current branch",
      handler: async (_args: string, ctx: ExtensionCommandContext) => {
        if (ctx.mode !== "tui") {
          ctx.ui.notify("/todos requires interactive mode", "error");
          return;
        }
        await ctx.ui.custom<void>((_tui, theme, _kb, done) =>
          createTodoOverlay(this.list, theme, () => done()),
        );
      },
    };
  }

  /**
   * Steering: track tool work and todo calls for the idle counter and push.
   *
   * @param event - Finished tool execution.
   */
  trackToolExecution(event: ToolExecutionEndEvent): void {
    this.workedSinceInput = true;
    if (TODO_TOOLS.has(event.toolName)) this.touchedThisTurn = true;
  }

  /**
   * Steering: count idle turns and queue a reminder once the limit is hit.
   *
   * @param event - Turn boundary with the entries proposed so far.
   * @returns A transcript record of the reminder, or nothing.
   */
  countIdleTurn(event: TurnEndEvent): TurnEndEventResult | undefined {
    if (this.touchedThisTurn) {
      this.touchedThisTurn = false;
      this.idleTurns = 0;
      return undefined;
    }
    this.idleTurns += 1;
    if (this.idleTurns < STEER_AFTER_TURNS) return undefined;
    if (event.outcome !== "completed" || event.toolResults.length === 0) {
      return undefined;
    }

    this.idleTurns = 0;
    const hint = idleHint(this.list);
    if (!hint) return undefined;
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
    if (!this.workedSinceInput || !hasUnfinished(this.list)) {
      return undefined;
    }
    this.pushedSinceInput = true;
    return {
      entries: [
        ...event.entries,
        {
          type: "custom_message",
          customType: CONTINUE_MESSAGE_TYPE,
          content: continueMessage(this.list),
          display: true,
        },
      ],
      continue: true,
    };
  }
}

/**
 * Register the todo extension with Pi.
 *
 * @param pi - Extension API used to register tools, commands and handlers.
 */
export default function todoExtension(pi: ExtensionAPI): void {
  const todo = new Todo();

  pi.registerTool(todo.createListTool());
  pi.registerTool(todo.createWriteTool());
  pi.registerTool(todo.createEditTool());
  pi.registerCommand("todos", todo.createCommand());
  pi.on("session_start", (_event, ctx) => todo.restore(ctx));
  pi.on("session_tree", (_event, ctx) => todo.restore(ctx));
  pi.on("input", () => todo.resetSteering());
  pi.on("tool_execution_end", (event) => todo.trackToolExecution(event));
  pi.on("turn_end", (event) => todo.countIdleTurn(event));
  pi.on("context_with_system", (event) => todo.injectHint(event));
  pi.on("agent_before_settle", (event) => todo.pushUnfinished(event));
  pi.registerEntryRenderer(HINT_ENTRY_TYPE, (_entry, _options, theme) =>
    renderHintEntry(pi.getSettings().outputPad ?? 1, theme),
  );
}
