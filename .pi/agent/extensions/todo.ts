/**
 * Todo Extension - a markdown-style checklist the agent plans with.
 *
 * The `todo` tool keeps one checklist per session branch:
 * - no arguments: view the list;
 * - `write`: replace the whole list (initial plan or major rework);
 * - `edits`: exact-text replacements applied by Pi's own edit tool, so a
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

/** Mutable state for one extension load. */
interface TodoRuntime {
  list: string;
  /** Turns since the last todo call, user input, or reminder. */
  idleTurns: number;
  /** Whether a todo call finished during the current turn. */
  touchedThisTurn: boolean;
  /** Reminder waiting to be appended to the next request. */
  pendingHint?: string;
  /** Whether a stopped agent was pushed since the last user input. */
  pushedSinceInput: boolean;
  /** Whether any tool ran since the last user input. */
  workedSinceInput: boolean;
}

const EditParams = Type.Object({
  oldText: Type.String({
    description: "Exact text of the current list to replace; must be unique.",
  }),
  newText: Type.String({ description: "Replacement text." }),
});

/** Schema for the todo tool. */
const TodoParams = Type.Object({
  write: Type.Optional(
    Type.String({
      description:
        "Replace the whole list with this Markdown checklist. Use for the initial plan or a major rework.",
    }),
  ),
  edits: Type.Optional(
    Type.Array(EditParams, {
      description:
        "Exact-text replacements on the current list, same rules as the edit tool.",
    }),
  ),
});

type TodoInput = Static<typeof TodoParams>;

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
 * @returns The edited checklist text, not yet validated.
 */
async function applyEdits(
  list: string,
  edits: NonNullable<TodoInput["edits"]>,
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
    "todo",
    { path: LIST_NAME, edits },
    undefined,
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
 * Run one todo call.
 *
 * @param runtime - Shared todo state.
 * @param params - Validated tool input.
 * @returns A result with the full list; failures leave the list unchanged.
 */
async function executeTodo(
  runtime: TodoRuntime,
  params: TodoInput,
): Promise<AgentToolResult<TodoDetails>> {
  if (params.write !== undefined && params.edits !== undefined) {
    return todoResult(
      runtime.list,
      "",
      "Pass either write or edits, not both.",
    );
  }
  if (params.write === undefined && params.edits === undefined) {
    return todoResult(runtime.list, "Viewed the todo list.");
  }

  try {
    const next =
      params.write !== undefined
        ? params.write
        : await applyEdits(runtime.list, params.edits ?? []);
    runtime.list = normalizeList(next);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return todoResult(runtime.list, "", message);
  }
  return todoResult(runtime.list, "Updated the todo list.");
}

/**
 * Rebuild the list from the active session branch.
 *
 * The latest `todo` result on the branch wins, so forks and branches see the
 * list that existed at that point in history.
 *
 * @param runtime - Shared todo state to reset.
 * @param ctx - Session context providing the active branch.
 */
function restoreState(runtime: TodoRuntime, ctx: ExtensionContext): void {
  runtime.list = "";
  resetSteering(runtime);

  for (const entry of ctx.sessionManager.getBranch()) {
    if (entry.type !== "message") continue;
    const message = entry.message;
    if (message.role !== "toolResult" || message.toolName !== "todo") continue;
    const details = message.details as TodoDetails | undefined;
    if (typeof details?.list !== "string") continue;
    runtime.list = details.list;
  }
}

/**
 * Reset the steering state after user input or a session change.
 *
 * @param runtime - Shared todo state.
 */
function resetSteering(runtime: TodoRuntime): void {
  runtime.idleTurns = 0;
  runtime.touchedThisTurn = false;
  runtime.pendingHint = undefined;
  runtime.pushedSinceInput = false;
  runtime.workedSinceInput = false;
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
    `If progress changed, update it with todo edits: mark the current item ${IN_PROGRESS_BOX}, finished items ${COMPLETED_BOX}, abandoned items ${CANCELLED_BOX}. Ignore this if the list is accurate.`,
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
    `If remaining items are blocked or no longer relevant, mark them ${CANCELLED_BOX} with todo edits, then stop.`,
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
 * Describe a call for its header line.
 *
 * @param args - Current tool call arguments.
 * @returns Short mode description.
 */
function describeCall(args: TodoInput): string {
  if (args.write !== undefined) return "write";
  if (args.edits !== undefined) return `edit (${args.edits.length})`;
  return "view";
}

/**
 * Build the `todo` tool definition.
 *
 * @param runtime - Shared todo state.
 * @returns Tool definition registered with Pi.
 */
function createTodoTool(
  runtime: TodoRuntime,
): ToolDefinition<typeof TodoParams, TodoDetails> {
  const editTool = createEditToolDefinition("/");
  return {
    name: "todo",
    label: "Todo",
    description: `Manage the session todo list, a Markdown checklist. Item markers: \`- ${PENDING_BOX}\` pending, \`- ${IN_PROGRESS_BOX}\` in progress (at most one), \`- ${COMPLETED_BOX}\` done, \`- ${CANCELLED_BOX}\` cancelled. Call with no arguments to view the list. \`write\` replaces the whole list. \`edits\` applies exact-text replacements like the edit tool: each oldText must match the current list exactly and uniquely, otherwise nothing changes. Every call returns the full list.`,
    promptSnippet: "Track multi-step work as a visible Markdown checklist",
    promptGuidelines: [
      "Use todo with write to plan before multi-step work whose progress is worth tracking (e.g. review then fix findings, multi-file changes, fix-test-commit loops), or when the user lists several items. Skip it for single-step or purely conversational requests.",
      `Use todo edits to mark an item ${IN_PROGRESS_BOX} when starting it and ${COMPLETED_BOX} right after finishing it, before starting the next one. Keep at most one item ${IN_PROGRESS_BOX}.`,
      `When requirements change mid-task, update todo first. Mark abandoned items ${CANCELLED_BOX} instead of deleting them.`,
    ],
    parameters: TodoParams,
    prepareArguments: editTool.prepareArguments as (args: unknown) => TodoInput,

    async execute(_toolCallId, params) {
      return executeTodo(runtime, params);
    },

    renderCall(args, theme) {
      return new Text(
        theme.fg("toolTitle", theme.bold("todo ")) +
          theme.fg("muted", describeCall(args)),
        0,
        0,
      );
    },

    renderResult(result, _options, theme) {
      const details = result.details;
      const lines = details.list
        ? renderItems(details.list, theme)
        : [theme.fg("dim", "No todos")];
      if (details.error) {
        lines.unshift(theme.fg("error", `Error: ${details.error}`));
      }
      return new Text(lines.join("\n"), 0, 0);
    },
  };
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
 * Build the `/todos` command.
 *
 * @param runtime - Shared todo state.
 * @returns Command definition registered with Pi.
 */
function createTodosCommand(runtime: TodoRuntime) {
  return {
    description: "Show the todo list on the current branch",
    handler: async (_args: string, ctx: ExtensionCommandContext) => {
      if (ctx.mode !== "tui") {
        ctx.ui.notify("/todos requires interactive mode", "error");
        return;
      }
      await ctx.ui.custom<void>((_tui, theme, _kb, done) =>
        createTodoOverlay(runtime.list, theme, () => done()),
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
  const runtime: TodoRuntime = {
    list: "",
    idleTurns: 0,
    touchedThisTurn: false,
    pushedSinceInput: false,
    workedSinceInput: false,
  };

  /**
   * Restore the list for the active branch on session start or tree moves.
   *
   * @param _event - Session event; only the context is needed.
   * @param ctx - Session context providing the active branch.
   */
  function restoreSession(_event: unknown, ctx: ExtensionContext): void {
    restoreState(runtime, ctx);
  }

  /** Steering: user input starts a fresh steering cycle. */
  function resetOnInput(): void {
    resetSteering(runtime);
  }

  /**
   * Steering: track tool work and todo calls for the idle counter and push.
   *
   * @param event - Finished tool execution.
   */
  function trackToolExecution(event: ToolExecutionEndEvent): void {
    runtime.workedSinceInput = true;
    if (event.toolName === "todo") runtime.touchedThisTurn = true;
  }

  /**
   * Steering: count idle turns and queue a reminder once the limit is hit.
   *
   * @param event - Turn boundary with the entries proposed so far.
   * @returns A transcript record of the reminder, or nothing.
   */
  function countIdleTurn(event: TurnEndEvent): TurnEndEventResult | undefined {
    if (runtime.touchedThisTurn) {
      runtime.touchedThisTurn = false;
      runtime.idleTurns = 0;
      return undefined;
    }
    runtime.idleTurns += 1;
    if (runtime.idleTurns < STEER_AFTER_TURNS) return undefined;
    if (event.outcome !== "completed" || event.toolResults.length === 0) {
      return undefined;
    }

    runtime.idleTurns = 0;
    const hint = idleHint(runtime.list);
    if (!hint) return undefined;
    runtime.pendingHint = hint;
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
  function injectHint(
    event: ContextWithSystemEvent,
  ): ContextEventResult | undefined {
    const hint = runtime.pendingHint;
    if (!hint) return undefined;
    runtime.pendingHint = undefined;
    const messages = withHint(event.messages, hint);
    return messages ? { messages } : undefined;
  }

  /**
   * Steering: push an agent that stops with unfinished items, once per input.
   *
   * @param event - Final boundary before the agent settles.
   * @returns A continue request with a visible message, or nothing.
   */
  function pushUnfinished(
    event: AgentBeforeSettleEvent,
  ): AgentBeforeSettleEventResult | undefined {
    if (event.outcome !== "completed" || runtime.pushedSinceInput) {
      return undefined;
    }
    // A reply without any tool call is discussion, not abandoned work.
    if (!runtime.workedSinceInput || !hasUnfinished(runtime.list)) {
      return undefined;
    }
    runtime.pushedSinceInput = true;
    return {
      entries: [
        ...event.entries,
        {
          type: "custom_message",
          customType: CONTINUE_MESSAGE_TYPE,
          content: continueMessage(runtime.list),
          display: true,
        },
      ],
      continue: true,
    };
  }

  /**
   * Steering: show a recorded reminder in the transcript.
   *
   * Pi does not pad custom entries, so the line applies the transcript's
   * `outputPad` setting itself to align with messages and tool output.
   *
   * @param _entry - Recorded reminder entry.
   * @param _options - Render options.
   * @param theme - Active theme.
   * @returns A one-line marker.
   */
  function renderHintEntry(
    _entry: unknown,
    _options: unknown,
    theme: Theme,
  ): Text {
    const padding = pi.getSettings().outputPad ?? 1;
    return new Text(
      theme.fg("dim", "Todo reminder sent to the agent"),
      padding,
      0,
    );
  }

  pi.on("session_start", restoreSession);
  pi.on("session_tree", restoreSession);
  pi.registerTool(createTodoTool(runtime));
  pi.registerCommand("todos", createTodosCommand(runtime));

  // Steering handlers.
  pi.on("input", resetOnInput);
  pi.on("tool_execution_end", trackToolExecution);
  pi.on("turn_end", countIdleTurn);
  pi.on("context_with_system", injectHint);
  pi.on("agent_before_settle", pushUnfinished);
  pi.registerEntryRenderer(HINT_ENTRY_TYPE, renderHintEntry);
}
