/**
 * Todo Extension - Demonstrates state management via session entries
 *
 * This extension:
 * - Registers a `todo` tool for the LLM to manage todos
 * - Registers a `/todos` command for users to view the list
 *
 * State is stored in tool result details (not external files), which allows
 * proper branching - when you branch, the todo state is automatically
 * correct for that point in history.
 */

import { StringEnum } from "@earendil-works/pi-ai";
import type {
  AgentToolResult,
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
  Theme,
  ToolDefinition,
  ToolRenderResultOptions,
} from "@earendil-works/pi-coding-agent";
import { matchesKey, Text, truncateToWidth } from "@earendil-works/pi-tui";
import { type Static, Type } from "typebox";

/** One todo item. */
interface Todo {
  id: number;
  text: string;
  done: boolean;
}

/** Actions accepted by the todo tool. */
type TodoAction = "list" | "add" | "toggle" | "clear";

/** Snapshot stored in every tool result for rendering and session replay. */
interface TodoDetails {
  action: TodoAction;
  todos: Todo[];
  nextId: number;
  error?: string;
}

/** Mutable state for one extension load. */
interface TodoRuntime {
  todos: Todo[];
  nextId: number;
}

/** Schema for the todo tool. */
const TodoParams = Type.Object({
  action: StringEnum(["list", "add", "toggle", "clear"] as const),
  text: Type.Optional(Type.String({ description: "Todo text (for add)" })),
  id: Type.Optional(Type.Number({ description: "Todo ID (for toggle)" })),
});

/** Input accepted by the todo tool. */
type TodoInput = Static<typeof TodoParams>;

/**
 * Format the current list for the model.
 *
 * @param todos - Todo items to format.
 * @returns One `[x] #id: text` line per item, or `No todos`.
 */
function formatTodos(todos: Todo[]): string {
  return todos.length
    ? todos
      .map((todo) => `[${todo.done ? "x" : " "}] #${todo.id}: ${todo.text}`)
      .join("\n")
    : "No todos";
}

/**
 * Capture the current list for this result and later session replay.
 *
 * The snapshot clones the items so later mutations do not rewrite history.
 *
 * @param runtime - Shared todo state.
 * @param action - Action that produced this snapshot.
 * @param error - Optional error code stored for rendering.
 * @returns A detached snapshot of the current list.
 */
function snapshot(
  runtime: TodoRuntime,
  action: TodoAction,
  error?: string,
): TodoDetails {
  return {
    action,
    todos: runtime.todos.map((todo) => ({ ...todo })),
    nextId: runtime.nextId,
    ...(error ? { error } : {}),
  };
}

/**
 * Build a tool result and persist the resulting state in its details.
 *
 * @param runtime - Shared todo state.
 * @param action - Action that produced this result.
 * @param text - Human-readable result sent to the model.
 * @param error - Optional error code stored for rendering.
 * @returns A tool result carrying the current todo snapshot.
 */
function todoResult(
  runtime: TodoRuntime,
  action: TodoAction,
  text: string,
  error?: string,
): AgentToolResult<TodoDetails> {
  return {
    content: [{ type: "text", text }],
    details: snapshot(runtime, action, error),
  };
}

/**
 * Rebuild runtime state from the active session branch.
 *
 * The latest `todo` tool result on the branch wins, so forks and branches
 * see the list that existed at that point in history.
 *
 * @param runtime - Shared todo state to replace.
 * @param ctx - Session context providing the active branch.
 */
function restoreState(runtime: TodoRuntime, ctx: ExtensionContext): void {
  runtime.todos = [];
  runtime.nextId = 1;

  for (const entry of ctx.sessionManager.getBranch()) {
    if (entry.type !== "message") continue;
    const message = entry.message;
    if (message.role !== "toolResult" || message.toolName !== "todo") continue;

    const details = message.details as TodoDetails | undefined;
    if (!details) continue;
    runtime.todos = details.todos;
    runtime.nextId = details.nextId;
  }
}

/**
 * Apply one todo action.
 *
 * @param runtime - Shared todo state.
 * @param params - Validated todo tool input.
 * @returns A tool result with the updated list.
 */
function executeTodo(
  runtime: TodoRuntime,
  params: TodoInput,
): AgentToolResult<TodoDetails> {
  switch (params.action) {
    case "list":
      return todoResult(runtime, "list", formatTodos(runtime.todos));

    case "add": {
      if (!params.text) {
        return todoResult(
          runtime,
          "add",
          "Error: text required for add",
          "text required",
        );
      }
      const todo: Todo = {
        id: runtime.nextId++,
        text: params.text,
        done: false,
      };
      runtime.todos.push(todo);
      return todoResult(runtime, "add", `Added todo #${todo.id}: ${todo.text}`);
    }

    case "toggle": {
      if (params.id === undefined) {
        return todoResult(
          runtime,
          "toggle",
          "Error: id required for toggle",
          "id required",
        );
      }
      const todo = runtime.todos.find((item) => item.id === params.id);
      if (!todo) {
        return todoResult(
          runtime,
          "toggle",
          `Todo #${params.id} not found`,
          `#${params.id} not found`,
        );
      }
      todo.done = !todo.done;
      return todoResult(
        runtime,
        "toggle",
        `Todo #${todo.id} ${todo.done ? "completed" : "uncompleted"}`,
      );
    }

    case "clear": {
      const count = runtime.todos.length;
      runtime.todos = [];
      runtime.nextId = 1;
      return todoResult(runtime, "clear", `Cleared ${count} todos`);
    }

    default:
      return todoResult(runtime, "list", "Unknown action", "unknown action");
  }
}

/**
 * Render the tool call header.
 *
 * @param args - Current tool call arguments.
 * @param theme - Active theme.
 * @returns A one-line call header.
 */
function renderTodoCall(args: TodoInput, theme: Theme): Text {
  const action = typeof args.action === "string" ? args.action : "";
  let text =
    theme.fg("toolTitle", theme.bold("todo ")) + theme.fg("muted", action);
  if (args.text) text += ` ${theme.fg("dim", `"${args.text}"`)}`;
  if (args.id !== undefined) text += ` ${theme.fg("accent", `#${args.id}`)}`;
  return new Text(text, 0, 0);
}

/**
 * Render a todo tool result.
 *
 * @param result - Final tool result and its todo snapshot.
 * @param options - Rendering options from Pi.
 * @param theme - Active theme.
 * @returns A compact result view; the expanded view shows all items.
 */
function renderTodoResult(
  result: AgentToolResult<TodoDetails>,
  options: ToolRenderResultOptions,
  theme: Theme,
): Text {
  const details = result.details;
  if (details.error) {
    return new Text(theme.fg("error", `Error: ${details.error}`), 0, 0);
  }

  const todos = details.todos;

  switch (details.action) {
    case "list": {
      if (todos.length === 0) {
        return new Text(theme.fg("dim", "No todos"), 0, 0);
      }
      let text = theme.fg("muted", `${todos.length} todo(s):`);
      const display = options.expanded ? todos : todos.slice(0, 5);
      for (const todo of display) {
        const check = todo.done
          ? theme.fg("success", "✓")
          : theme.fg("dim", "○");
        const item = todo.done
          ? theme.fg("dim", todo.text)
          : theme.fg("muted", todo.text);
        text += `\n${check} ${theme.fg("accent", `#${todo.id}`)} ${item}`;
      }
      if (!options.expanded && todos.length > 5) {
        text += `\n${theme.fg("dim", `... ${todos.length - 5} more`)}`;
      }
      return new Text(text, 0, 0);
    }

    case "add": {
      const added = todos[todos.length - 1];
      return new Text(
        theme.fg("success", "✓ Added ") +
        theme.fg("accent", `#${added.id}`) +
        " " +
        theme.fg("muted", added.text),
        0,
        0,
      );
    }

    case "toggle": {
      const message = result.content[0];
      const text = message?.type === "text" ? message.text : "";
      return new Text(
        theme.fg("success", "✓ ") + theme.fg("muted", text),
        0,
        0,
      );
    }

    case "clear":
      return new Text(
        theme.fg("success", "✓ ") + theme.fg("muted", "Cleared all todos"),
        0,
        0,
      );

    default:
      return new Text(
        result.content[0]?.type === "text"
          ? theme.fg("error", result.content[0].text)
          : "",
        0,
        0,
      );
  }
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
  return {
    name: "todo",
    label: "Todo",
    description:
      "Manage a todo list. Actions: list, add (text), toggle (id), clear",
    promptSnippet: "Track multi-step tasks as a visible checklist",
    promptGuidelines: [
      "Use todo to add a plan before starting complex, multi-step tasks (e.g. review then fix several findings, multi-file changes, fix-test-commit loops), or when the user lists several items.",
      "Use todo with action=toggle to mark an item done right after finishing it, before starting the next item.",
      "When the user adds or changes requirements mid-task, update todo first (clear stale items, add new ones).",
    ],
    parameters: TodoParams,

    async execute(_toolCallId, params) {
      return executeTodo(runtime, params);
    },

    renderCall(args, theme) {
      return renderTodoCall(args, theme);
    },

    renderResult(result, options, theme) {
      return renderTodoResult(result, options, theme);
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
    description: "Show all todos on the current branch",
    handler: async (_args: string, ctx: ExtensionCommandContext) => {
      if (ctx.mode !== "tui") {
        ctx.ui.notify("/todos requires interactive mode", "error");
        return;
      }

      await ctx.ui.custom<void>((_tui, theme, _kb, done) => {
        return new TodoListComponent(runtime.todos, theme, () => done());
      });
    },
  };
}

/**
 * Overlay component for the `/todos` command.
 *
 * The component caches rendered lines per width so repeated frames do not
 * rebuild the whole list.
 */
class TodoListComponent {
  private todos: Todo[];
  private theme: Theme;
  private onClose: () => void;
  private cachedWidth?: number;
  private cachedLines?: string[];

  /**
   * Create the overlay.
   *
   * @param todos - Todo items to display.
   * @param theme - Active theme.
   * @param onClose - Closes the overlay.
   */
  constructor(todos: Todo[], theme: Theme, onClose: () => void) {
    this.todos = todos;
    this.theme = theme;
    this.onClose = onClose;
  }

  /**
   * Close the overlay on Escape or Ctrl+C.
   *
   * @param data - Raw terminal input.
   */
  handleInput(data: string): void {
    if (matchesKey(data, "escape") || matchesKey(data, "ctrl+c")) {
      this.onClose();
    }
  }

  /**
   * Render the current todo list.
   *
   * @param width - Available terminal columns.
   * @returns Cached overlay lines for this width.
   */
  render(width: number): string[] {
    if (this.cachedLines && this.cachedWidth === width) {
      return this.cachedLines;
    }

    const lines: string[] = [];
    const th = this.theme;

    lines.push("");
    const title = th.fg("accent", " Todos ");
    const headerLine =
      th.fg("borderMuted", "─".repeat(3)) +
      title +
      th.fg("borderMuted", "─".repeat(Math.max(0, width - 10)));
    lines.push(truncateToWidth(headerLine, width));
    lines.push("");

    if (this.todos.length === 0) {
      lines.push(
        truncateToWidth(
          `  ${th.fg("dim", "No todos yet. Ask the agent to add some!")}`,
          width,
        ),
      );
    } else {
      const done = this.todos.filter((t) => t.done).length;
      const total = this.todos.length;
      lines.push(
        truncateToWidth(
          `  ${th.fg("muted", `${done}/${total} completed`)}`,
          width,
        ),
      );
      lines.push("");

      for (const todo of this.todos) {
        const check = todo.done ? th.fg("success", "✓") : th.fg("dim", "○");
        const id = th.fg("accent", `#${todo.id}`);
        const text = todo.done
          ? th.fg("dim", todo.text)
          : th.fg("text", todo.text);
        lines.push(truncateToWidth(`  ${check} ${id} ${text}`, width));
      }
    }

    lines.push("");
    lines.push(
      truncateToWidth(`  ${th.fg("dim", "Press Escape to close")}`, width),
    );
    lines.push("");

    this.cachedWidth = width;
    this.cachedLines = lines;
    return lines;
  }

  /** Drop cached render state so the next frame rebuilds it. */
  invalidate(): void {
    this.cachedWidth = undefined;
    this.cachedLines = undefined;
  }
}

/**
 * Register the todo extension with Pi.
 *
 * @param pi - Extension API used to register tools and commands.
 */
export default function todoExtension(pi: ExtensionAPI): void {
  const runtime: TodoRuntime = { todos: [], nextId: 1 };

  pi.on("session_start", (_event, ctx) => restoreState(runtime, ctx));
  pi.on("session_tree", (_event, ctx) => restoreState(runtime, ctx));
  pi.registerTool(createTodoTool(runtime));
  pi.registerCommand("todos", createTodosCommand(runtime));
}
