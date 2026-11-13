import assert from "node:assert/strict";
import test, { describe } from "node:test";

import { Agent } from "@earendil-works/pi-agent-core";
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai";

import todoExtension from "../extensions/todo.ts";

/** Load the extension with a fake `pi` that only records registrations. */
function setup() {
  const tools = new Map();
  const hooks = new Map();
  const commands = new Map();
  todoExtension({
    registerTool: (definition) => {
      tools.set(definition.name, definition);
    },
    registerCommand: (name, command) => commands.set(name, command),
    registerEntryRenderer() {},
    on: (name, handler) => hooks.set(name, handler),
  });
  const run = (name, params, signal) =>
    tools.get(name).execute("test", params, signal);
  const view = () => run("todo_list", {});
  const write = (list, signal) => run("todo_write", { list }, signal);
  const edit = (edits, signal) => run("todo_edit", { edits }, signal);
  const list = async () => (await view()).details.list;
  return { tools, hooks, commands, view, write, edit, list };
}

const done = (item) => ({ oldText: `- [ ] ${item}`, newText: `- [x] ${item}` });

describe("todo", () => {
  describe("the todo tools", () => {
    test("the three todo tools share one checklist", async () => {
      const { view, write, edit, list } = setup();

      await write("- [ ] A\n- [ ] B");
      assert.equal(await list(), "- [ ] A\n- [ ] B");

      const shown = await view();
      assert.match(shown.content[0].text, /- \[ \] A\n- \[ \] B/);

      await edit([done("A")]);
      assert.equal(await list(), "- [x] A\n- [ ] B");
    });

    test("several items may be in progress at once", async () => {
      const { write, edit, list } = setup();

      await write("- [~] A\n- [~] B\n- [ ] C");
      assert.equal(await list(), "- [~] A\n- [~] B\n- [ ] C");

      await edit([
        { oldText: "- [ ] C", newText: "- [~] C" },
        { oldText: "- [~] A", newText: "- [x] A" },
      ]);
      assert.equal(await list(), "- [x] A\n- [~] B\n- [~] C");
    });

    test("each todo action has its own tool and parameters", () => {
      const { tools } = setup();

      assert.deepEqual([...tools.keys()], ["todo_list", "todo_write", "todo_edit"]);
      assert.deepEqual(tools.get("todo_list").parameters.properties, {});
      assert.deepEqual(Object.keys(tools.get("todo_write").parameters.properties), [
        "list",
      ]);
      assert.deepEqual(Object.keys(tools.get("todo_edit").parameters.properties), [
        "edits",
      ]);
      for (const tool of tools.values()) {
        assert.equal(tool.executionMode, "sequential");
      }
    });
  });

  describe("checklist state", () => {
    /** Build an assistant message for the fake model. */
    function reply(content, stopReason) {
      return {
        role: "assistant",
        api: "openai-completions",
        provider: "test",
        model: "test",
        timestamp: 0,
        stopReason,
        content,
        usage: {
          input: 0,
          output: 0,
          cacheRead: 0,
          cacheWrite: 0,
          totalTokens: 0,
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
        },
      };
    }

    /**
     * Let Pi's real agent run several todo calls from one model reply.
     *
     * The model is fake: it sends the given calls once, then says "Done".
     */
    async function sendTogether(tools, calls) {
      const model = {
        id: "test",
        name: "test",
        api: "openai-completions",
        provider: "test",
        baseUrl: "https://example.invalid",
        input: ["text"],
        reasoning: false,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: 1000,
        maxTokens: 100,
      };
      const replies = [
        reply(
          calls.map(({ name, args }, index) => ({
            type: "toolCall",
            id: String(index),
            name,
            arguments: args,
          })),
          "toolUse",
        ),
        reply([{ type: "text", text: "Done" }], "stop"),
      ];
      const agent = new Agent({
        initialState: { model, tools: [...tools.values()] },
        streamFn: () => {
          const message = replies.shift();
          const stream = createAssistantMessageEventStream();
          stream.push({ type: "done", reason: message.stopReason, message });
          stream.end();
          return stream;
        },
      });
      await agent.prompt("Update the checklist");
    }

    test("todo_write rejects a bad update and keeps the old checklist", async () => {
      const { write, list } = setup();
      await write("- [ ] A");

      const result = await write("not a checklist");

      assert.equal(result.isError, true);
      assert.equal(await list(), "- [ ] A");
    });

    test("todo restores the latest checklist when switching session branches", async () => {
      const { hooks, list } = setup();
      const todoResult = (toolName, list) => ({
        type: "message",
        message: { role: "toolResult", toolName, details: { list } },
      });
      const branch = (entries) => ({
        sessionManager: { getBranch: () => entries },
      });

      hooks.get("session_start")(
        {},
        branch([
          todoResult("todo_write", "- [ ] A"),
          todoResult("todo_edit", "- [x] A"),
        ]),
      );
      assert.equal(await list(), "- [x] A");

      hooks.get("session_tree")({}, branch([]));
      assert.equal(await list(), "");
    });

    test("two edits sent at once both stay in the checklist", async () => {
      const { tools, write, list } = setup();
      await write("- [ ] A\n- [ ] B");

      await sendTogether(tools, [
        { name: "todo_edit", args: { edits: [done("A")] } },
        { name: "todo_edit", args: { edits: [done("B")] } },
      ]);

      assert.equal(await list(), "- [x] A\n- [x] B");
    });

    test("a cancelled call does not change the checklist", async () => {
      const { write, edit, list } = setup();
      await write("- [ ] A");

      const calls = [
        (signal) => write("- [x] A", signal),
        (signal) => edit([done("A")], signal),
      ];
      for (const call of calls) {
        await assert.rejects(call(AbortSignal.abort()));
        assert.equal(await list(), "- [ ] A");
      }
    });
  });

  describe("steering reminders", () => {
    /** Simulate one busy turn that never touches todo. */
    function workTurn(hooks) {
      hooks.get("tool_execution_end")({ toolName: "read" });
      const turnEnd = { outcome: "completed", toolResults: [{}], entries: [] };
      return hooks.get("turn_end")(turnEnd);
    }

    /** Simulate busy turns that never touch todo, until a reminder is queued. */
    function idleUntilReminder(hooks) {
      for (let turn = 0; turn < 100; turn++) {
        const result = workTurn(hooks);
        if (result) return result;
      }
      assert.fail("no reminder after 100 idle turns");
    }

    /** Turns before the stale-list reminder, as in the extension. */
    const REMIND_STALE_LIST_AFTER_TURNS = 16;
    /** Turns before the new-task reminder, as in the extension. */
    const REMIND_NEW_TASK_AFTER_TURNS = 32;

    test("an agent without a checklist is left alone until the new-task window", () => {
      const { hooks } = setup();

      // Busy turns that never use todo stay below the new-task limit.
      for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++) {
        assert.equal(workTurn(hooks), undefined);
      }
      const settle = { outcome: "completed", entries: [] };
      assert.equal(hooks.get("agent_before_settle")(settle), undefined);
    });

    test("a long run without a checklist asks for one", async () => {
      const { hooks } = setup();
      const history = [
        { role: "user", content: [{ type: "text", text: "Do a long task" }] },
        {
          role: "toolResult",
          toolName: "bash",
          content: [{ type: "text", text: "output" }],
        },
      ];

      for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++) workTurn(hooks);
      const turnEnd = workTurn(hooks);
      assert.deepEqual(
        turnEnd.entries.map((entry) => [entry.type, entry.customType]),
        [["custom", "todo-hint"]],
      );

      const request = hooks.get("context_with_system")({ messages: history });
      const reminder = request.messages.at(-1).content.at(-1).text;
      assert.match(reminder, /<todo-reminder>/);
      assert.match(
        reminder,
        new RegExp(`${REMIND_NEW_TASK_AFTER_TURNS} turns without user input`),
      );
      assert.match(reminder, /todo_write/);
      assert.match(reminder, /todo_edit/);
      assert.match(reminder, /The todo list is empty\./);
      assert.equal(history[1].content.length, 1);

      // The limit restarts, so the next reminder waits another full window.
      assert.equal(hooks.get("context_with_system")({ messages: history }), undefined);
      for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++) {
        assert.equal(workTurn(hooks), undefined);
      }
      assert.ok(workTurn(hooks));
    });

    test("user input restarts the new-task count", () => {
      const { hooks } = setup();

      for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++) workTurn(hooks);
      hooks.get("input")({});
      for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++) {
        assert.equal(workTurn(hooks), undefined);
      }
    });

    test("a todo call restarts the new-task count", () => {
      const { hooks } = setup();

      for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++) workTurn(hooks);
      // One turn that views the checklist restarts the whole window.
      hooks.get("tool_execution_end")({ toolName: "todo_list" });
      const turnEnd = hooks.get("turn_end")({
        outcome: "completed",
        toolResults: [{}],
        entries: [],
      });
      assert.equal(turnEnd, undefined);

      for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++) {
        assert.equal(workTurn(hooks), undefined);
      }
      assert.ok(workTurn(hooks));
    });

    test("a fully closed list is asked for a new checklist", async () => {
      const { hooks, write } = setup();
      await write("- [x] A\n- [-] B");

      // A closed list has nothing to nudge about, so only the new-task hint fires.
      for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++) {
        assert.equal(workTurn(hooks), undefined);
      }
      const turnEnd = workTurn(hooks);
      const reminder = turnEnd.entries.at(-1).data.hint;
      assert.match(reminder, /<todo-reminder>/);
      assert.match(
        reminder,
        new RegExp(`${REMIND_NEW_TASK_AFTER_TURNS} turns without user input`),
      );
      // The checklist gets its own block so it cannot absorb what follows it.
      assert.match(
        reminder,
        /Current todo list:\n\n- \[x\] A\n- \[-\] B\n<\/todo-reminder>$/,
      );
    });

    test("unfinished items never get the new-task reminder", async () => {
      const { hooks, write } = setup();
      await write("- [ ] A");

      // Stale-list nudges keep firing every REMIND_STALE_LIST_AFTER_TURNS turns
      // while the new-task window counts past its limit, but the unfinished item
      // keeps that reminder silent.
      const reminderTurns = [];
      const horizon = REMIND_NEW_TASK_AFTER_TURNS + REMIND_STALE_LIST_AFTER_TURNS;
      for (let turn = 1; turn <= horizon; turn++) {
        const turnEnd = workTurn(hooks);
        if (!turnEnd) continue;
        reminderTurns.push(turn);
        const reminder = turnEnd.entries.at(-1).data.hint;
        assert.match(reminder, /recently\.\n\n- \[ \] A\n\nIf progress changed/);
        assert.doesNotMatch(reminder, /without user input/);
      }
      assert.deepEqual(reminderTurns, [16, 32, 48]);
    });

    test("stalled turns never queue a reminder", () => {
      const { hooks } = setup();
      const stalledTurn = (outcome, toolResults) =>
        hooks.get("turn_end")({ outcome, toolResults, entries: [] });

      // Turns that did not finish, or finished without any tool result, stay
      // silent even once the counters are past the long horizon.
      for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++) workTurn(hooks);
      for (let turn = 0; turn < 5; turn++) {
        assert.equal(stalledTurn("aborted", [{}]), undefined);
        assert.equal(stalledTurn("completed", []), undefined);
      }
    });

    test("a queued reminder is dropped when new input arrives first", async () => {
      const { hooks, write } = setup();
      await write("- [ ] A");
      idleUntilReminder(hooks);

      // The next request carries a fresh user message, not a tool result.
      const request = hooks.get("context_with_system")({
        messages: [{ role: "user", content: [{ type: "text", text: "Wait" }] }],
      });
      assert.equal(request, undefined);

      // The reminder was dropped, not saved for a later request.
      const history = [
        { role: "user", content: [{ type: "text", text: "Do A" }] },
        {
          role: "toolResult",
          toolName: "read",
          content: [{ type: "text", text: "file" }],
        },
      ];
      assert.equal(
        hooks.get("context_with_system")({ messages: history }),
        undefined,
      );
    });

    test("a restored session restarts the steering counters", () => {
      const { hooks } = setup();
      const branch = { sessionManager: { getBranch: () => [] } };

      for (const event of ["session_start", "session_tree"]) {
        for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++) workTurn(hooks);
        hooks.get(event)({}, branch);
        for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++) {
          assert.equal(workTurn(hooks), undefined);
        }
        assert.ok(workTurn(hooks));
      }
    });

    test("long idle work with unfinished items reminds the next request only", async () => {
      const { hooks, write } = setup();
      await write("- [ ] A");
      const history = [
        { role: "user", content: [{ type: "text", text: "Do A" }] },
        {
          role: "toolResult",
          toolName: "read",
          content: [{ type: "text", text: "file" }],
        },
      ];

      const turnEnd = idleUntilReminder(hooks);
      // The transcript only gets a display marker, not the reminder message.
      assert.deepEqual(
        turnEnd.entries.map((entry) => [entry.type, entry.customType]),
        [["custom", "todo-hint"]],
      );

      const request = hooks.get("context_with_system")({ messages: history });
      const reminder = request.messages.at(-1).content.at(-1).text;
      assert.match(reminder, /<todo-reminder>/);
      assert.match(reminder, /- \[ \] A/);
      assert.match(reminder, /todo_edit/);
      assert.equal(history[1].content.length, 1);

      assert.equal(
        hooks.get("context_with_system")({ messages: history }),
        undefined,
      );
    });
  });

  describe("stopping with unfinished items", () => {
    test("stopping with unfinished items asks the agent to continue once", async () => {
      const { hooks, write } = setup();
      await write("- [x] A\n- [ ] B");
      hooks.get("input")({});
      hooks.get("tool_execution_end")({ toolName: "read" });
      const settle = { outcome: "completed", entries: [] };

      const pushed = hooks.get("agent_before_settle")(settle);
      assert.equal(pushed.continue, true);
      assert.match(
        pushed.entries[0].content,
        /unfinished items:\n\n- \[x\] A\n- \[ \] B\n\nContinue with the next item/,
      );

      assert.equal(hooks.get("agent_before_settle")(settle), undefined);
    });

    test("stopping with every item closed does not ask the agent to continue", async () => {
      const { hooks, write } = setup();
      await write("- [x] A\n- [-] B");
      hooks.get("input")({});
      hooks.get("tool_execution_end")({ toolName: "read" });

      const settle = { outcome: "completed", entries: [] };
      assert.equal(hooks.get("agent_before_settle")(settle), undefined);
    });
  });

  describe("the /todos view", () => {
    /**
     * A fake extension UI that opens a custom component like the TUI mode does.
     *
     * @param t - Node test context, used to dispose a component left open.
     * @param rows - Terminal height the component sees.
     * @returns The fake UI and the open component.
     */
    function fakeUI(t, rows) {
      let component;
      const tui = { requestRender() {}, terminal: { rows } };
      const theme = { fg: (_color, text) => text, bold: (text) => text };
      t.after(() => component?.dispose?.());
      return {
        get component() {
          return component;
        },
        ui: {
          notify: () => assert.fail("TUI mode must not notify"),
          custom(factory) {
            return new Promise((resolve) => {
              const done = () => {
                const closing = component;
                component = undefined;
                closing?.dispose?.();
                resolve();
              };
              component = factory(tui, theme, undefined, done);
            });
          },
        },
      };
    }

    test("keeps its hint inside a short terminal and scrolls the items", async (t) => {
      const { commands, write } = setup();
      const rows = 20;
      // Rows pi keeps around the page are assumed to be 4; the fake UI cannot
      // verify the real reserve, but a page that grows past it would clip.
      const piRows = 4;
      const items = Array.from({ length: 12 }, (_, index) => `- [ ] item ${index}`);
      await write(items.join("\n"));

      const screen = fakeUI(t, rows);
      const showing = commands.get("todos").handler("", {
        mode: "tui",
        ui: screen.ui,
      });
      const overlay = screen.component;

      /** The list as the user sees it, in a terminal this short. */
      const shown = () => {
        const lines = overlay.render(80);
        assert.ok(
          lines.length <= rows - piRows,
          `page leaves pi its rows: ${lines.length} of ${rows}`,
        );
        return lines.join("\n");
      };

      const first = shown();
      assert.match(first, /Todos/);
      assert.match(first, /0\/12 closed/);
      assert.match(first, /Press Escape to close/);
      assert.match(first, /item 0\b/);
      assert.doesNotMatch(first, /item 11\b/);

      // Paging down reaches the items the window hides.
      for (let page = 0; page < 3; page += 1) overlay.handleInput("\x1b[6~");
      const later = shown();
      assert.match(later, /item 11\b/);
      assert.match(later, /Press Escape to close/);

      // Paging back up returns to the head of the list.
      for (let page = 0; page < 3; page += 1) overlay.handleInput("\x1b[5~");
      assert.match(shown(), /item 0\b/);

      overlay.handleInput("\x1b");
      await showing;
      assert.equal(screen.component, undefined, "Escape closes the overlay");
    });
  });

  describe("rendering", () => {
    /** Render a tool result as plain text. */
    function render(tool, result) {
      const theme = { fg: (_color, text) => text };
      return tool
        .renderResult(result, {}, theme)
        .render(1000)
        .map((line) => line.trimEnd())
        .join("\n");
    }

    test("each todo call names its own tool in the header", () => {
      const { tools } = setup();
      const theme = { fg: (_color, text) => text, bold: (text) => text };
      const header = (name, args) =>
        tools
          .get(name)
          .renderCall(args, theme)
          .render(1000)
          .map((line) => line.trimEnd())
          .join("\n");

      assert.equal(header("todo_list", {}), "todo_list");
      assert.equal(
        header("todo_write", { list: "- [ ] A\n- [ ] B" }),
        "todo_write (2 items)",
      );
      assert.equal(
        header("todo_edit", { edits: [done("A")] }),
        "todo_edit (1 edit)",
      );
    });

    test("a rejected call shows Pi's error, not 'No todos'", () => {
      const { tools } = setup();
      // Pi's own errors (bad arguments, blocked calls) carry no checklist.
      const result = {
        content: [{ type: "text", text: "Tool execution was blocked" }],
        details: {},
      };

      assert.equal(
        render(tools.get("todo_list"), result),
        "Tool execution was blocked",
      );
    });
  });
});
