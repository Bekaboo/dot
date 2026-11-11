/**
 * Integration regression tests for subagent result delivery.
 *
 * The real extension runs inside an SDK `AgentSession`, driven by a scripted
 * faux model stream. The child process is a controllable fake, so every step
 * is deterministic and nothing touches a model, the network, or a real child.
 *
 * The contract under test: a finished child is queued as a steering message
 * with `triggerTurn`, so a busy parent sees it in its next request (before the
 * run settles) and an idle parent is woken into a new turn.
 */

import assert from "node:assert/strict";
import { createRequire } from "node:module";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import test from "node:test";

const require = createRequire(import.meta.url);

/** Children created by the fake `spawn`, oldest first. */
const children = [];

/**
 * A controllable child process for the extension.
 *
 * @returns A fake child that can emit stdout and close on demand.
 */
function fakeChild() {
  const listeners = new Map();
  const child = {
    exitCode: null,
    signalCode: null,
    stdout: {
      setEncoding() {},
      on(event, handler) {
        listeners.set(`stdout:${event}`, handler);
      },
    },
    stderr: {
      setEncoding() {},
      on(event, handler) {
        listeners.set(`stderr:${event}`, handler);
      },
    },
    on(event, handler) {
      listeners.set(event, handler);
    },
    once(event, handler) {
      listeners.set(event, handler);
    },
    kill(signal) {
      if (signal === "SIGKILL") child.close(null, signal);
    },
    /** Push a chunk through the child's stdout handler. */
    write(text) {
      listeners.get("stdout:data")?.(text);
    },
    /** Finish the child with an exit code. */
    close(code = 0, signal = null) {
      child.exitCode = code;
      child.signalCode = signal;
      listeners.get("close")?.(code, signal);
    },
  };
  children.push(child);
  return child;
}

// The extension imports `spawn` with an ESM named import, which snapshots the
// property when the module is evaluated. Patch it before that load, then
// restore it so the SDK and the rest of the process keep the real `spawn`.
const childProcess = process.getBuiltinModule("node:child_process");
const realSpawn = childProcess.spawn;
childProcess.spawn = fakeChild;
const extensionPath = require.resolve("../extensions/subagent.ts");
const loadSubagent = require(extensionPath).default ?? require(extensionPath);
childProcess.spawn = realSpawn;

const { fauxAssistantMessage, fauxProvider, fauxToolCall } = await import(
  "@earendil-works/pi-ai"
);
const {
  createAgentSession,
  DefaultResourceLoader,
  ModelRuntime,
  SessionManager,
  SettingsManager,
} = await import("@earendil-works/pi-coding-agent");

/** Deterministic model: every response is scripted per test. */
const faux = fauxProvider({ provider: "faux", models: [{ id: "faux-1" }] });
const modelRuntime = await ModelRuntime.create({
  modelsPath: null,
  refreshOnCreate: false,
  allowModelNetwork: false,
});
modelRuntime.registerNativeProvider(faux.provider);

/** A JSONL record carrying a completed assistant message. */
function assistantRecord(text) {
  return `${JSON.stringify({
    type: "message_end",
    message: { role: "assistant", content: [{ type: "text", text }] },
  })}\n`;
}

/**
 * Wait until a predicate holds or the timeout expires.
 *
 * @param predicate - Condition to poll.
 * @param timeoutMs - How long to wait, in milliseconds.
 * @returns Whether the predicate holds at the end.
 */
async function waitFor(predicate, timeoutMs = 1_000) {
  const deadline = Date.now() + timeoutMs;
  while (!predicate() && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  return predicate();
}

/**
 * Create an idle SDK session with the real extension loaded.
 *
 * @param t - Node test context, used for cleanup.
 * @param customTools - Extra tools the scripted parent may call.
 * @param tools - Active tool names.
 * @returns The created session.
 */
async function createSession(t, customTools = [], tools = ["subagent"]) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-subagent-delivery-"));
  const resourceLoader = new DefaultResourceLoader({
    cwd: dir,
    agentDir: dir,
    noExtensions: true,
    noSkills: true,
    noPromptTemplates: true,
    noThemes: true,
    noContextFiles: true,
    systemPrompt: "You are a test assistant.",
    extensionFactories: [loadSubagent],
  });
  await resourceLoader.reload();
  const { session } = await createAgentSession({
    cwd: dir,
    agentDir: dir,
    modelRuntime,
    model: faux.getModel(),
    thinkingLevel: "off",
    resourceLoader,
    sessionManager: SessionManager.inMemory(),
    settingsManager: SettingsManager.inMemory({
      compaction: { enabled: false },
      retry: { enabled: false },
    }),
    noTools: "all",
    tools,
    customTools,
  });
  t.after(() => {
    session.dispose();
    fs.rmSync(dir, { recursive: true, force: true });
  });
  return session;
}

test("a busy parent sees the result in its next request, before it settles", async (t) => {
  children.length = 0;
  const previousGrace = process.env.SUBAGENT_KILL_GRACE_MS;
  process.env.SUBAGENT_KILL_GRACE_MS = "20";
  t.after(() => {
    if (previousGrace === undefined) delete process.env.SUBAGENT_KILL_GRACE_MS;
    else process.env.SUBAGENT_KILL_GRACE_MS = previousGrace;
  });

  let releaseWait;
  let waitStarted = false;
  const waitTool = {
    name: "wait",
    label: "Wait",
    description: "Block until the test releases it.",
    parameters: { type: "object", properties: {} },
    async execute() {
      waitStarted = true;
      return new Promise((resolve) => {
        releaseWait = () =>
          resolve({ content: [{ type: "text", text: "released" }], details: {} });
      });
    },
  };

  const session = await createSession(t, [waitTool], ["subagent", "wait"]);
  const requests = [];
  let settled = false;
  session.subscribe((event) => {
    if (event.type === "agent_settled") settled = true;
  });

  // Observe delivery mode through the agent queue, not extension internals.
  const steered = [];
  const followed = [];
  const steer = session.agent.steer.bind(session.agent);
  const followUp = session.agent.followUp.bind(session.agent);
  session.agent.steer = (message) => {
    steered.push(message);
    steer(message);
  };
  session.agent.followUp = (message) => {
    followed.push(message);
    followUp(message);
  };

  faux.setResponses([
    (context) => {
      requests.push({ context, settled });
      return fauxAssistantMessage(
        fauxToolCall("subagent", { id: "slow", prompt: "work" }),
      );
    },
    (context) => {
      requests.push({ context, settled });
      return fauxAssistantMessage(fauxToolCall("wait", {}));
    },
    (context) => {
      requests.push({ context, settled });
      return fauxAssistantMessage("parent finished");
    },
  ]);

  const run = session.prompt("start");
  try {
    assert.ok(await waitFor(() => waitStarted), "the parent reached its busy tool");
    assert.equal(children.length, 1, "the extension spawned one fake child");

    children[0].write(assistantRecord("child answer"));
    children[0].close(0);

    assert.ok(
      await waitFor(() => steered.length > 0),
      "a finished child is steered while the parent is still in a tool",
    );
    assert.equal(followed.length, 0, "the result is not deferred as a follow-up");
    assert.match(JSON.stringify(steered[0]), /child answer/);

    releaseWait();
    await run;
  } finally {
    releaseWait?.();
    // Let the run finish even when an assertion above failed, so no work leaks
    // past the test and the session can be disposed cleanly.
    await run.catch(() => {});
  }

  assert.equal(requests.length, 3);
  assert.match(
    JSON.stringify(requests[2].context.messages),
    /\[subagent slow\] finished in \d+s\.[\s\S]*child answer/,
  );
  assert.equal(
    requests[2].settled,
    false,
    "the notice reaches the model before the parent run settles",
  );
});

test("an idle parent is woken into a new request", async (t) => {
  children.length = 0;
  const session = await createSession(t);
  const requests = [];
  let settled = false;
  session.subscribe((event) => {
    if (event.type === "agent_settled") settled = true;
  });

  faux.setResponses([
    (context) => {
      requests.push({ context, settled });
      return fauxAssistantMessage(
        fauxToolCall("subagent", { id: "late", prompt: "work" }),
      );
    },
    (context) => {
      requests.push({ context, settled });
      return fauxAssistantMessage("first run done");
    },
    (context) => {
      requests.push({ context, settled });
      return fauxAssistantMessage("woken by the subagent");
    },
  ]);

  await session.prompt("start");
  assert.equal(requests.length, 2);
  assert.equal(children.length, 1);

  children[0].write(assistantRecord("late child answer"));
  children[0].close(0);

  assert.ok(
    await waitFor(() => requests.length === 3),
    "an idle parent starts a new request when the result arrives",
  );
  await session.waitForIdle();

  assert.match(
    JSON.stringify(requests[2].context.messages),
    /\[subagent late\] finished in \d+s\.[\s\S]*late child answer/,
  );
  assert.equal(requests[2].settled, true, "the wake starts after the parent was idle");
  assert.equal(session.getLastAssistantText(), "woken by the subagent");
});
