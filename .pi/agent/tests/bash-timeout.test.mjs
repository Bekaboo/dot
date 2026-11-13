import assert from "node:assert/strict";
import test, { describe } from "node:test";

import bashTimeout, { DEFAULT_TIMEOUT_SEC } from "../extensions/bash-timeout.ts";

/** Load the extension with a fake `pi` that only records hooks. */
function setup() {
  const hooks = new Map();
  bashTimeout({ on: (name, handler) => hooks.set(name, handler) });
  const toolCall = (toolName, input) => {
    const event = { type: "tool_call", toolName, input };
    hooks.get("tool_call")(event);
    return event.input;
  };
  const startAgent = (toolGuidelines) => {
    hooks.get("before_agent_start")({
      systemPromptOptions: { toolGuidelines },
    });
    return toolGuidelines;
  };
  return { toolCall, startAgent };
}

describe("bash-timeout", () => {
  test("bash without a timeout gets the default timeout", () => {
    const { toolCall } = setup();

    assert.equal(
      toolCall("bash", { command: "sleep 1" }).timeout,
      DEFAULT_TIMEOUT_SEC,
    );
  });

  test("bash keeps a timeout the model chose", () => {
    const { toolCall } = setup();

    assert.equal(
      toolCall("bash", { command: "make", timeout: 600 }).timeout,
      600,
    );
  });

  test("other tools are left unchanged", () => {
    const { toolCall } = setup();

    assert.deepEqual(toolCall("read", { path: "a.txt" }), { path: "a.txt" });
  });

  test("the prompt tells the model about the default timeout once", () => {
    const { startAgent } = setup();
    const guidelines = {};

    startAgent(guidelines);
    startAgent(guidelines);

    assert.equal(guidelines.bash.length, 1);
    assert.ok(
      guidelines.bash[0].includes(`killed after ${DEFAULT_TIMEOUT_SEC} seconds`),
    );
  });

  test("the timeout guideline is added after existing bash guidelines", () => {
    const { startAgent } = setup();

    const guidelines = startAgent({ bash: ["Prefer rg over grep."] });

    assert.equal(guidelines.bash[0], "Prefer rg over grep.");
    assert.equal(guidelines.bash.length, 2);
  });
});
