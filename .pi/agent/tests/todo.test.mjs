import assert from "node:assert/strict";
import test from "node:test";

import { Agent } from "@earendil-works/pi-agent-core";
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai";

import todoExtension from "../extensions/todo.ts";

/** Load the extension with a fake `pi` that only records registrations. */
function setup() {
  let tool;
  const hooks = new Map();
  todoExtension({
    registerTool: (definition) => {
      tool = definition;
    },
    registerCommand() {},
    registerEntryRenderer() {},
    on: (name, handler) => hooks.set(name, handler),
  });
  const call = (params = {}, signal) => tool.execute("test", params, signal);
  const list = async () => (await call()).details.list;
  return { tool, hooks, call, list };
}

/** Render a tool result as plain text. */
function render(tool, result) {
  const theme = { fg: (_color, text) => text };
  return tool
    .renderResult(result, {}, theme)
    .render(1000)
    .map((line) => line.trimEnd())
    .join("\n");
}

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
async function sendTogether(tool, calls) {
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
      calls.map((args, index) => ({
        type: "toolCall",
        id: String(index),
        name: "todo",
        arguments: args,
      })),
      "toolUse",
    ),
    reply([{ type: "text", text: "Done" }], "stop"),
  ];
  const agent = new Agent({
    initialState: { model, tools: [tool] },
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

/** Simulate busy turns that never touch todo, until a reminder is queued. */
function idleUntilReminder(hooks) {
  for (let turn = 0; turn < 100; turn++) {
    hooks.get("tool_execution_end")({ toolName: "read" });
    const turnEnd = { outcome: "completed", toolResults: [{}], entries: [] };
    const result = hooks.get("turn_end")(turnEnd);
    if (result) return result;
  }
  assert.fail("no reminder after 100 idle turns");
}

const done = (item) => ({ oldText: `- [ ] ${item}`, newText: `- [x] ${item}` });

test("todo writes, shows, and edits a checklist", async () => {
  const { call, list } = setup();

  await call({ write: "- [ ] A\n- [ ] B" });
  assert.equal(await list(), "- [ ] A\n- [ ] B");

  await call({ edits: [done("A")] });
  assert.equal(await list(), "- [x] A\n- [ ] B");
});

test("todo rejects a bad update and keeps the old checklist", async () => {
  const { call, list } = setup();
  await call({ write: "- [ ] A" });

  const result = await call({ write: "not a checklist" });

  assert.equal(result.isError, true);
  assert.equal(await list(), "- [ ] A");
});

test("todo restores the latest checklist when switching session branches", async () => {
  const { hooks, list } = setup();
  const todoResult = (list) => ({
    type: "message",
    message: { role: "toolResult", toolName: "todo", details: { list } },
  });
  const branch = (entries) => ({
    sessionManager: { getBranch: () => entries },
  });

  hooks.get("session_start")(
    {},
    branch([todoResult("- [ ] A"), todoResult("- [x] A")]),
  );
  assert.equal(await list(), "- [x] A");

  hooks.get("session_tree")({}, branch([]));
  assert.equal(await list(), "");
});

test("two edits sent at once both stay in the checklist", async () => {
  const { tool, call, list } = setup();
  await call({ write: "- [ ] A\n- [ ] B" });

  await sendTogether(tool, [{ edits: [done("A")] }, { edits: [done("B")] }]);

  assert.equal(await list(), "- [x] A\n- [x] B");
});

test("a rejected call shows Pi's error, not 'No todos'", () => {
  const { tool } = setup();
  // Pi's own errors (bad arguments, blocked calls) carry no checklist.
  const result = {
    content: [{ type: "text", text: "Tool execution was blocked" }],
    details: {},
  };

  assert.equal(render(tool, result), "Tool execution was blocked");
});

test("a cancelled call does not change the checklist", async () => {
  const { call, list } = setup();
  await call({ write: "- [ ] A" });

  for (const params of [{ write: "- [x] A" }, { edits: [done("A")] }]) {
    await assert.rejects(call(params, AbortSignal.abort()));
    assert.equal(await list(), "- [ ] A");
  }
});

test("no todo reminders when the agent never made a checklist", () => {
  const { hooks } = setup();

  // Many busy turns that never use todo.
  for (let turn = 0; turn < 100; turn++) {
    hooks.get("tool_execution_end")({ toolName: "read" });
    const turnEnd = { outcome: "completed", toolResults: [{}], entries: [] };
    assert.equal(hooks.get("turn_end")(turnEnd), undefined);
  }
  const settle = { outcome: "completed", entries: [] };
  assert.equal(hooks.get("agent_before_settle")(settle), undefined);
});

test("long idle work with unfinished items reminds the next request only", async () => {
  const { hooks, call } = setup();
  await call({ write: "- [ ] A" });
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
  assert.equal(history[1].content.length, 1);

  assert.equal(
    hooks.get("context_with_system")({ messages: history }),
    undefined,
  );
});

test("stopping with unfinished items asks the agent to continue once", async () => {
  const { hooks, call } = setup();
  await call({ write: "- [x] A\n- [ ] B" });
  hooks.get("input")({});
  hooks.get("tool_execution_end")({ toolName: "read" });
  const settle = { outcome: "completed", entries: [] };

  const pushed = hooks.get("agent_before_settle")(settle);
  assert.equal(pushed.continue, true);
  assert.match(
    pushed.entries[0].content,
    /unfinished items:\n- \[x\] A\n- \[ \] B/,
  );

  assert.equal(hooks.get("agent_before_settle")(settle), undefined);
});

test("stopping with every item closed does not ask the agent to continue", async () => {
  const { hooks, call } = setup();
  await call({ write: "- [x] A\n- [-] B" });
  hooks.get("input")({});
  hooks.get("tool_execution_end")({ toolName: "read" });

  const settle = { outcome: "completed", entries: [] };
  assert.equal(hooks.get("agent_before_settle")(settle), undefined);
});
