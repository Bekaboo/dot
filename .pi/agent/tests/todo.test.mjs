import assert from "node:assert/strict";
import test, { describe } from "node:test";

import { Agent } from "@earendil-works/pi-agent-core";
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai";

import todoExtension, {
  CONTINUE_QUIET_SEC,
  REMIND_FOLLOW_UP_TURNS,
  REMIND_NEW_TASK_AFTER_TURNS,
  REMIND_STALE_LIST_AFTER_TURNS,
} from "../extensions/todo.ts";
import { VIEWPORT_RESERVE_ROWS } from "../extensions/utils/page.ts";

/** Load the extension with a fake `pi` that only records registrations. */
function setup() {
  const tools = new Map();
  const hooks = new Map();
  const commands = new Map();
  const messages = [];
  todoExtension({
    registerTool: (definition) => {
      tools.set(definition.name, definition);
    },
    registerCommand: (name, command) => commands.set(name, command),
    registerEntryRenderer() {},
    sendMessage: (message, options) => messages.push({ message, options }),
    on: (name, handler) => hooks.set(name, handler),
  });
  const run = (name, params, signal) =>
    tools.get(name).execute("test", params, signal);
  const view = () => run("todo_list", {});
  const write = (list, signal) => run("todo_write", { list }, signal);
  const edit = (edits, signal) => run("todo_edit", { edits }, signal);
  const list = async () => (await view()).details.list;
  return { tools, hooks, commands, messages, view, write, edit, list };
}

const done = (item) => ({ oldText: `- [ ] ${item}`, newText: `- [x] ${item}` });

/** Wall-clock instant the stop-to-continue tests start their mocked clock at. */
const PROMPTED_AT = Date.parse("2026-11-18T09:00:00Z");

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

    test("each todo action has its own tool and parameters", () => {
      const { tools } = setup();

      assert.deepEqual(
        [...tools.keys()],
        ["todo_list", "todo_write", "todo_edit"],
      );
      assert.deepEqual(tools.get("todo_list").parameters.properties, {});
      assert.deepEqual(
        Object.keys(tools.get("todo_write").parameters.properties),
        ["list"],
      );
      assert.deepEqual(
        Object.keys(tools.get("todo_edit").parameters.properties),
        ["edits"],
      );
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

    test("items waiting on the user are a status of their own", async () => {
      const { write, list } = setup();

      // A blocked item sits next to an in-progress one without counting towards
      // the single in-progress slot.
      await write("- [!] A\n- [~] B");
      assert.equal(await list(), "- [!] A\n- [~] B");
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

      for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++)
        workTurn(hooks);
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

      // The window restarts, but follow-ups repeat every REMIND_FOLLOW_UP_TURNS.
      assert.equal(
        hooks.get("context_with_system")({ messages: history }),
        undefined,
      );
      for (let turn = 0; turn < REMIND_FOLLOW_UP_TURNS - 1; turn++) {
        assert.equal(workTurn(hooks), undefined);
      }
      const followUp = workTurn(hooks);
      // The hint names the turns actually worked, not just the first window.
      assert.match(
        followUp.entries.at(-1).data.hint,
        new RegExp(
          `${REMIND_NEW_TASK_AFTER_TURNS + REMIND_FOLLOW_UP_TURNS} turns without user input`,
        ),
      );
    });

    test("user input restarts the new-task count", () => {
      const { hooks } = setup();

      for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++)
        workTurn(hooks);
      hooks.get("input")({ source: "interactive" }, { hasUI: true });
      for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++) {
        assert.equal(workTurn(hooks), undefined);
      }
    });

    test("a todo call restarts the new-task count", () => {
      const { hooks } = setup();

      for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++)
        workTurn(hooks);
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

      // Stale-list nudges open at REMIND_STALE_LIST_AFTER_TURNS, then repeat
      // every REMIND_FOLLOW_UP_TURNS while the new-task window counts past its
      // own limit; the unfinished item keeps that reminder silent.
      const reminderTurns = [];
      const horizon =
        REMIND_NEW_TASK_AFTER_TURNS + REMIND_STALE_LIST_AFTER_TURNS;
      for (let turn = 1; turn <= horizon; turn++) {
        const turnEnd = workTurn(hooks);
        if (!turnEnd) continue;
        reminderTurns.push(turn);
        const reminder = turnEnd.entries.at(-1).data.hint;
        assert.match(
          reminder,
          /recently\.\n\n- \[ \] A\n\nIf progress changed/,
        );
        assert.doesNotMatch(reminder, /without user input/);
      }
      const staleTurns = [];
      for (
        let turn = REMIND_STALE_LIST_AFTER_TURNS;
        turn <= horizon;
        turn += REMIND_FOLLOW_UP_TURNS
      ) {
        staleTurns.push(turn);
      }
      assert.deepEqual(reminderTurns, staleTurns);
    });

    test("an all-blocked list still gets the stale-list hint", async () => {
      const { hooks, write } = setup();
      await write("- [!] A");

      const hint = idleUntilReminder(hooks).entries.at(-1).data.hint;
      // Blocked work is unfinished, so it keeps the list fresh until the agent
      // clears the marker; it is not a reason to ask for a new plan.
      assert.match(hint, /recently\.\n\n- \[!\] A\n/);
      assert.doesNotMatch(hint, /without user input/);
    });

    test("a todo call restarts the stale-list window, not just its follow-up", async () => {
      const { hooks, write } = setup();
      await write("- [ ] A");
      idleUntilReminder(hooks);

      // Touching the list clears the initial window along with the follow-up.
      hooks.get("tool_execution_end")({ toolName: "todo_edit" });
      hooks.get("turn_end")({
        outcome: "completed",
        toolResults: [{}],
        entries: [],
      });

      for (let turn = 0; turn < REMIND_STALE_LIST_AFTER_TURNS - 1; turn++) {
        assert.equal(workTurn(hooks), undefined);
      }
      assert.ok(workTurn(hooks));
    });

    test("stalled turns never queue a reminder", () => {
      const { hooks } = setup();
      const stalledTurn = (outcome, toolResults) =>
        hooks.get("turn_end")({ outcome, toolResults, entries: [] });

      // Turns that did not finish, or finished without any tool result, stay
      // silent even once the counters are past the long horizon.
      for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++)
        workTurn(hooks);
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
        for (let turn = 0; turn < REMIND_NEW_TASK_AFTER_TURNS - 1; turn++)
          workTurn(hooks);
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

  describe("stopping with actionable items", () => {
    /**
     * Install the mocked clock these timing tests measure against.
     *
     * Node refuses a second install, so this runs once per test.
     *
     * @param t - Node test context, which owns the mocked clock.
     */
    function armClock(t) {
      t.mock.timers.enable({ apis: ["Date", "setTimeout"], now: PROMPTED_AT });
    }

    /**
     * Fire one prompt, as Pi reports it.
     *
     * @param hooks - Extension hooks recorded by `setup()`.
     * @param mode - `hasUI` of its context: false is a headless run.
     * @param source - Where the input came from, as Pi reports it.
     */
    function prompted(hooks, { hasUI = true, source = "interactive" } = {}) {
      hooks.get("input")({ source }, { hasUI });
    }

    /** Move the clock through the reading window that opens at settle. */
    function userLeft(t) {
      t.mock.timers.tick(CONTINUE_QUIET_SEC * 1000);
    }

    /** A session manager as the shared wake contract sees it. */
    function fakeSession() {
      return { getSessionId: () => "test-session" };
    }

    test("stopping with actionable items asks the agent to continue on every stop", async (t) => {
      const { hooks, write } = setup();
      await write("- [x] A\n- [ ] B");
      armClock(t);
      prompted(hooks, { hasUI: false });
      hooks.get("tool_execution_end")({ toolName: "read" });
      userLeft(t);
      const settle = { outcome: "completed", entries: [] };

      const pushed = hooks.get("agent_before_settle")(settle);
      assert.equal(pushed.continue, true);
      assert.match(
        pushed.entries[0].content,
        /actionable items:\n\n- \[ \] B\n\nContinue with the next one/,
      );
      // The push teaches the status that would have kept it silent.
      assert.match(pushed.entries[0].content, /mark it \[!\] .*todo_edit/);

      const pushedAgain = hooks.get("agent_before_settle")(settle);
      assert.equal(pushedAgain.continue, true);
      assert.match(pushedAgain.entries[0].content, /- \[ \] B/);
    });

    test("a new user message restores the quiet window after an earlier push", async (t) => {
      const { hooks, write, messages } = setup();
      await write("- [ ] A");
      armClock(t);
      prompted(hooks, { hasUI: false });
      hooks.get("tool_execution_end")({ toolName: "read" });
      userLeft(t);
      const settle = { outcome: "completed", entries: [] };
      assert.equal(hooks.get("agent_before_settle")(settle).continue, true);

      // Once the first push has gone out, later stops need no further delay.
      assert.equal(hooks.get("agent_before_settle")(settle).continue, true);

      // A new human message means the next reply is their conversation again.
      prompted(hooks);
      hooks.get("tool_execution_end")({ toolName: "read" });
      assert.equal(hooks.get("agent_before_settle")(settle), undefined);
      assert.deepEqual(messages, []);

      userLeft(t);
      assert.equal(messages.length, 1);
    });

    test("a stop while the user is still there holds the push instead of sending it", async (t) => {
      const { hooks, write, messages } = setup();
      await write("- [x] A\n- [ ] B");
      armClock(t);
      prompted(hooks);
      hooks.get("tool_execution_end")({ toolName: "read" });
      const settle = { outcome: "completed", entries: [] };

      // The user asked a question and the agent just answered it.
      assert.equal(hooks.get("agent_before_settle")(settle), undefined);
      assert.deepEqual(messages, []);

      t.mock.timers.tick(CONTINUE_QUIET_SEC * 1000 - 1);
      assert.deepEqual(messages, []);

      // Nobody wrote again, so the work the agent left behind is picked up.
      t.mock.timers.tick(1);
      assert.equal(messages.length, 1);
      assert.match(
        messages[0].message.content,
        /actionable items:\n\n- \[ \] B\n\nContinue with the next one/,
      );
      assert.equal(messages[0].message.display, true);
      // The held push starts a run of its own, like any other wake.
      assert.equal(messages[0].options.triggerTurn, true);
    });

    test("a long reply still gets a full reading window without tool calls", async (t) => {
      const { hooks, write, messages } = setup();
      await write("- [ ] A");
      armClock(t);
      prompted(hooks);

      // The model took longer than the old prompt-relative window and answered
      // without calling a tool. The user still needs time to read that answer.
      userLeft(t);
      const settle = { outcome: "completed", entries: [] };
      assert.equal(hooks.get("agent_before_settle")(settle), undefined);
      assert.deepEqual(messages, []);

      t.mock.timers.tick(CONTINUE_QUIET_SEC * 1000 - 1);
      assert.deepEqual(messages, []);
      t.mock.timers.tick(1);
      assert.equal(messages.length, 1);
      assert.match(messages[0].message.content, /- \[ \] A/);

      // Once the first push went out, an autonomous stop has no reading window.
      assert.equal(hooks.get("agent_before_settle")(settle).continue, true);
    });

    test("a held push wakes the session it was armed in", async (t) => {
      const { hooks, write, messages } = setup();
      // A restored session knows the manager it may wake, unlike a bare one.
      const sessionManager = { ...fakeSession(), getBranch: () => [] };
      hooks.get("session_start")({}, { sessionManager });
      await write("- [ ] A");
      armClock(t);
      prompted(hooks);
      hooks.get("tool_execution_end")({ toolName: "read" });
      hooks.get("agent_before_settle")({ outcome: "completed", entries: [] });

      userLeft(t);
      assert.equal(messages.length, 1);
      assert.match(messages[0].message.content, /- \[ \] A/);
    });

    test("the next user message cancels the held push", async (t) => {
      const { hooks, write, messages } = setup();
      await write("- [ ] A");
      armClock(t);
      prompted(hooks);
      hooks.get("tool_execution_end")({ toolName: "read" });
      hooks.get("agent_before_settle")({ outcome: "completed", entries: [] });

      // The user keeps the conversation going, so the stop answered them.
      prompted(hooks);
      userLeft(t);
      assert.deepEqual(messages, []);
    });

    test("a headless prompt leaves the push armed", async (t) => {
      const { hooks, write, messages } = setup();
      await write("- [ ] A");
      armClock(t);
      // No front end can show a `pi -p` prompt to anyone.
      prompted(hooks, { hasUI: false });
      hooks.get("tool_execution_end")({ toolName: "read" });

      const settle = { outcome: "completed", entries: [] };
      assert.equal(hooks.get("agent_before_settle")(settle).continue, true);
      assert.deepEqual(messages, []);
    });

    test("a restored session waits for the quiet window before continuing actionable items", async (t) => {
      const { hooks, write, messages } = setup();
      await write("- [ ] A");
      armClock(t);

      // A reload or restart restores the checklist but not the old timer.
      const branch = [
        {
          type: "message",
          message: {
            role: "toolResult",
            toolName: "todo_write",
            details: { list: "- [ ] A" },
          },
        },
      ];
      const sessionManager = { ...fakeSession(), getBranch: () => branch };
      hooks.get("session_start")({}, { sessionManager });
      assert.deepEqual(messages, []);

      // Even a run that settles immediately cannot bypass the restore window.
      const settle = { outcome: "completed", entries: [] };
      assert.equal(hooks.get("agent_before_settle")(settle), undefined);
      t.mock.timers.tick(CONTINUE_QUIET_SEC * 1000 - 1);
      assert.deepEqual(messages, []);

      // No user input arrived, so the restored work wakes on its own.
      t.mock.timers.tick(1);
      assert.equal(messages.length, 1);
      assert.match(messages[0].message.content, /- \[ \] A/);
      assert.equal(messages[0].options.triggerTurn, true);
    });

    test("an injected wake re-arms the push a human prompt held", async (t) => {
      const { hooks, write } = setup();
      await write("- [ ] A");
      armClock(t);
      prompted(hooks);
      hooks.get("tool_execution_end")({ toolName: "read" });
      hooks.get("agent_before_settle")({ outcome: "completed", entries: [] });

      // An intercom message is nobody's answer, so that run may be pushed.
      prompted(hooks, { source: "extension" });
      hooks.get("tool_execution_end")({ toolName: "read" });
      const settle = { outcome: "completed", entries: [] };
      assert.equal(hooks.get("agent_before_settle")(settle).continue, true);
    });

    test("a checklist that closed in the window needs no held push", async (t) => {
      const { hooks, write, edit, messages } = setup();
      await write("- [x] A\n- [ ] B");
      armClock(t);
      prompted(hooks);
      hooks.get("tool_execution_end")({ toolName: "read" });
      hooks.get("agent_before_settle")({ outcome: "completed", entries: [] });

      await edit([done("B")]);
      userLeft(t);
      assert.deepEqual(messages, []);
    });

    test("a held push waits out a run already in flight", async (t) => {
      const { hooks, write, messages } = setup();
      await write("- [ ] A");
      armClock(t);
      prompted(hooks);
      hooks.get("tool_execution_end")({ toolName: "read" });
      hooks.get("agent_before_settle")({ outcome: "completed", entries: [] });

      // A job tick woke the session, so pushing now would talk over it.
      hooks.get("agent_start")({}, { sessionManager: fakeSession() });
      userLeft(t);
      assert.deepEqual(messages, []);

      // That run's own stop carries the push instead.
      hooks.get("agent_settled")({});
      const settle = { outcome: "completed", entries: [] };
      assert.equal(hooks.get("agent_before_settle")(settle).continue, true);
    });

    test("a steer mid-run restarts the quiet window", async (t) => {
      const { hooks, write, messages } = setup();
      await write("- [ ] A");
      armClock(t);
      prompted(hooks);
      hooks.get("tool_execution_end")({ toolName: "read" });
      userLeft(t);

      // The user interrupted the run, so the stop that follows answers them.
      prompted(hooks);
      hooks.get("tool_execution_end")({ toolName: "read" });
      const settle = { outcome: "completed", entries: [] };
      assert.equal(hooks.get("agent_before_settle")(settle), undefined);
      assert.deepEqual(messages, []);

      t.mock.timers.tick(CONTINUE_QUIET_SEC * 1000 - 1);
      assert.deepEqual(messages, []);

      // Their window runs out like any other, with nobody writing again.
      t.mock.timers.tick(1);
      assert.equal(messages.length, 1);
    });

    test("an extension prompt leaves the push armed", async (t) => {
      const { hooks, write } = setup();
      await write("- [ ] A");
      armClock(t);
      prompted(hooks, { source: "extension" });
      hooks.get("tool_execution_end")({ toolName: "read" });

      // No human is waiting on a prompt another extension injected.
      const settle = { outcome: "completed", entries: [] };
      assert.equal(hooks.get("agent_before_settle")(settle).continue, true);
    });

    test("items waiting on the user do not ask the agent to continue", async (t) => {
      const { hooks, write, list } = setup();
      await write("- [x] A\n- [!] B\n- [!] C");
      // Without the write taking effect, an empty list would pass this test for
      // the wrong reason.
      assert.equal(await list(), "- [x] A\n- [!] B\n- [!] C");
      armClock(t);
      prompted(hooks);
      hooks.get("tool_execution_end")({ toolName: "read" });
      userLeft(t);

      const settle = { outcome: "completed", entries: [] };
      assert.equal(hooks.get("agent_before_settle")(settle), undefined);
    });

    test("one actionable item next to blocked ones still asks to continue", async (t) => {
      const { hooks, write } = setup();
      await write("- [!] A\n- [ ] B");
      armClock(t);
      prompted(hooks, { hasUI: false });
      hooks.get("tool_execution_end")({ toolName: "read" });
      userLeft(t);

      const pushed = hooks.get("agent_before_settle")({
        outcome: "completed",
        entries: [],
      });
      assert.equal(pushed.continue, true);
      assert.match(
        pushed.entries[0].content,
        /actionable items:\n\n- \[ \] B\n/,
      );
      assert.doesNotMatch(pushed.entries[0].content, /- \[!\] A/);
    });

    test("a long checklist travels as its actionable items only", async (t) => {
      const { hooks, write } = setup();
      const closed = Array.from(
        { length: 40 },
        (_, index) => `- [x] finished work ${index}`,
      );
      await write(
        ["- [!] waits on a peer", "- [ ] next step", ...closed].join("\n"),
      );
      armClock(t);
      prompted(hooks, { hasUI: false });
      hooks.get("tool_execution_end")({ toolName: "read" });
      userLeft(t);

      const pushed = hooks.get("agent_before_settle")({
        outcome: "completed",
        entries: [],
      });
      const content = pushed.entries[0].content;
      assert.match(content, /- \[ \] next step/);
      assert.doesNotMatch(content, /finished work/);
      assert.ok(content.length < 500, `push stays small: ${content.length}`);
    });

    test("stopping with every item closed does not ask the agent to continue", async (t) => {
      const { hooks, write, list } = setup();
      await write("- [x] A\n- [-] B");
      assert.equal(await list(), "- [x] A\n- [-] B");
      armClock(t);
      prompted(hooks);
      hooks.get("tool_execution_end")({ toolName: "read" });
      userLeft(t);

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
      const theme = {
        fg: (_color, text) => text,
        bold: (text) => text,
        bg: (_color, text) => text,
      };
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
      // The fake UI cannot verify the real reserve, but a page that grows past
      // it would clip.
      const items = Array.from(
        { length: 12 },
        (_, index) => `- [ ] item ${index}`,
      );
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
          lines.length <= rows - VIEWPORT_RESERVE_ROWS,
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
      const theme = {
        fg: (_color, text) => text,
        bold: (text) => text,
        bg: (_color, text) => text,
      };
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
