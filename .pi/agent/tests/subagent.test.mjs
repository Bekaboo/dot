/**
 * Tests for the subagent extension.
 *
 * The extension spawns a real pi process, so the interesting behaviour is the
 * seam around it: how a call becomes a child invocation, how the child's JSONL
 * output is read, how a finished child is reported, and that a child which
 * ends without an answer cannot pass as a success. Most tests drive the
 * registered tools with a fake `pi`, and the extension's `spawn` is swapped for
 * a fake, so every child outcome is reproducible without a model or a network.
 *
 * The last two tests run the real extension inside an SDK `AgentSession`,
 * driven by a scripted faux model stream. They pin the delivery contract: a
 * finished child is queued as a steering message with `triggerTurn`, so a busy
 * parent sees it in its next request (before the run settles) and an idle
 * parent is woken into a new turn.
 */

import assert from "node:assert/strict";
import * as fs from "node:fs";
import { createRequire } from "node:module";
import * as os from "node:os";
import * as path from "node:path";
import test, { describe } from "node:test";

const require = createRequire(import.meta.url);

/** Timeout for a notification or a request that never arrives. */
const NOTICE_TIMEOUT_MS = 2_000;

/**
 * Real working directory for every fake call.
 *
 * The extension checks that a call's cwd is a directory, so the fake `pi`
 * points at a directory the test owns instead of a made-up path.
 */
const workDir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-subagent-work-"));
test.after(() => {
  fs.rmSync(workDir, { recursive: true, force: true });
});

/**
 * Children created by the fake `spawn`, oldest first.
 *
 * One stub for every test keeps the extension's module cache intact, which
 * matters because each test needs a fresh instance: calling the factory again
 * installs a new instance against a fresh fake `pi` instead of re-importing
 * the module.
 */
const children = [];

/**
 * A controllable child process for the extension.
 *
 * @param command - Command the extension asked to spawn.
 * @param args - Arguments for that command.
 * @param options - Spawn options.
 * @returns A fake child that can emit output, close, or fail on demand.
 */
function fakeChild(command, args, options) {
  // Several listeners can share one event: the extension's result handler and
  // the stop helper both wait for `close`.
  const listeners = new Map();
  const add = (event, handler) => {
    const handlers = listeners.get(event) ?? new Set();
    handlers.add(handler);
    listeners.set(event, handlers);
  };
  const emit = (event, ...values) => {
    for (const handler of listeners.get(event) ?? []) handler(...values);
  };
  const child = {
    command,
    args,
    options,
    exitCode: null,
    signalCode: null,
    kills: [],
    stdout: {
      setEncoding() {},
      on(event, handler) {
        add(`stdout:${event}`, handler);
      },
    },
    stderr: {
      setEncoding() {},
      on(event, handler) {
        add(`stderr:${event}`, handler);
      },
    },
    stdin: {
      writes: [],
      writable: true,
      destroyed: false,
      on(event, handler) {
        add(`stdin:${event}`, handler);
      },
      write(text, done) {
        this.writes.push(text);
        done?.(null);
      },
    },
    on(event, handler) {
      add(event, handler);
    },
    once(event, handler) {
      add(event, handler);
    },
    kill(signal) {
      child.kills.push(signal);
      // A real process dies from the signal; close so stopProcess resolves.
      if (signal === "SIGKILL") child.close(null, signal);
    },
    /** Push text through the stdout handler, as a chunk of output. */
    write(text) {
      emit("stdout:data", text);
    },
    /** Finish the child with an exit code. */
    close(code = 0, signal = null) {
      child.exitCode = code;
      child.signalCode = signal;
      emit("close", code, signal);
    },
    /** Fail the spawn itself, as a missing executable would. */
    fail(message) {
      emit("error", new Error(message));
    },
  };
  children.push(child);
  return child;
}

// The extension imports `spawn` with an ESM named import, which snapshots the
// property when the module is evaluated. Patch it before that first load, then
// restore it so the SDK and the rest of the process keep the real `spawn`.
// Built-in modules are shared singletons, so the extension keeps the fake.
const childProcess = process.getBuiltinModule("node:child_process");
const realSpawn = childProcess.spawn;
childProcess.spawn = fakeChild;
const extensionPath = require.resolve("../extensions/subagent.ts");
const extensionModule = require(extensionPath);
childProcess.spawn = realSpawn;

/**
 * The extension factory: call it with a `pi` API to install a fresh instance.
 */
const installSubagent = extensionModule.default ?? extensionModule;

/** Cursor the `/subagents` list draws in front of the selected row. */
const {
  DEFAULT_TIMEOUT_SEC,
  MAX_RECORD_BYTES,
  SELECTED_CURSOR,
  VIEWPORT_RESERVE_ROWS,
} = extensionModule;

const { fauxAssistantMessage, fauxProvider, fauxToolCall } = await import(
  "@earendil-works/pi-ai"
);
const { KeybindingsManager, TUI_KEYBINDINGS } = await import(
  "@earendil-works/pi-tui"
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

/**
 * Wait until a predicate holds or the timeout expires.
 *
 * @param predicate - Condition to poll.
 * @param timeoutMs - How long to wait, in milliseconds.
 * @returns Whether the predicate holds at the end.
 */
async function waitFor(predicate, timeoutMs = NOTICE_TIMEOUT_MS) {
  const deadline = Date.now() + timeoutMs;
  while (!predicate() && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  return predicate();
}

/** A JSONL record carrying a completed assistant message. */
function assistantRecord(text, extra = {}) {
  return `${JSON.stringify({
    type: "message_end",
    message: { role: "assistant", content: [{ type: "text", text }], ...extra },
  })}\n`;
}

/** One JSONL record of the shape the child writes to stdout. */
const rpcRecord = (record) => `${JSON.stringify(record)}\n`;

/**
 * A JSONL record carrying one streamed assistant content-block update.
 *
 * @param event - Assistant message event, as the wire carries it.
 */
function updateRecord(event) {
  return `${JSON.stringify({ type: "message_update", assistantMessageEvent: event })}\n`;
}

/**
 * A JSONL record starting or ending a tool call.
 *
 * @param type - `tool_execution_start` or `tool_execution_end`.
 * @param toolCallId - Call the record belongs to.
 * @param toolName - Tool the child called.
 * @param args - Arguments of the call, only read on start.
 */
function toolRecord(type, toolCallId, toolName, args = {}) {
  return `${JSON.stringify({ type, toolCallId, toolName, args })}\n`;
}

/**
 * A JSONL record carrying a lifecycle event with no payload.
 *
 * @param type - Session event type, such as `agent_start` or `agent_settled`.
 */
function eventRecord(type) {
  return `${JSON.stringify({ type })}\n`;
}

/**
 * A JSONL record starting a message with the given role.
 *
 * @param role - Message role, `user` or `assistant`.
 */
function messageStartRecord(role) {
  return `${JSON.stringify({
    type: "message_start",
    message: { role, content: [] },
  })}\n`;
}

/**
 * A JSONL record ending a message with the given role and content.
 *
 * @param role - Message role, `user` or `assistant`.
 * @param content - Content blocks of the finished message.
 */
function messageEndRecord(role, content = []) {
  return `${JSON.stringify({
    type: "message_end",
    message: { role, content },
  })}\n`;
}

/**
 * A JSONL record carrying an assistant message that calls the finish tool.
 *
 * @param answer - Answer the child passes to `subagent_finish`.
 * @param text - Text in the same message, or omitted for none.
 */
function finishRecord(answer, text) {
  const content = text ? [{ type: "text", text }] : [];
  content.push({
    type: "toolCall",
    id: "finish-call",
    name: "subagent_finish",
    arguments: { answer },
  });
  return `${JSON.stringify({
    type: "message_end",
    message: { role: "assistant", content },
  })}\n`;
}

/**
 * A fake `pi` that records what the extension registers and sends.
 *
 * @param sessionName - Name this session was given, as another extension reads it.
 */
function fakePi(sessionName) {
  const tools = new Map();
  const commands = new Map();
  const hooks = new Map();
  const sent = [];
  return {
    tools,
    commands,
    hooks,
    sent,
    api: {
      registerTool: (definition) => tools.set(definition.name, definition),
      registerCommand: (name, definition) => commands.set(name, definition),
      on: (name, handler) => hooks.set(name, handler),
      sendMessage: (message, options) => sent.push({ message, options }),
      getSessionName: () => sessionName,
    },
  };
}

/**
 * How the extension launched the child pi, as pi itself would read it.
 *
 * Options are read by name rather than by position, so the assertions can state
 * what the child gets -- its session name, model, tools -- without pinning the
 * order or the exact spelling a current build happens to use.
 *
 * @param child - Fake child created by `spawn`.
 * @returns Option values by name, and the set of flags the child was given.
 */
const childOptions = (child) => {
  const options = {};
  const flags = new Set();
  for (let i = 0; i < child.args.length; i++) {
    const arg = child.args[i];
    if (!arg.startsWith("-")) continue;
    const [flag, inlineValue] = arg.split("=");
    const name = flag.replace(/^-+/, "");
    flags.add(name);
    const next = child.args[i + 1];
    if (inlineValue !== undefined) options[name] = inlineValue;
    else if (next !== undefined && !next.startsWith("-"))
      options[name] = child.args[++i];
  }
  return { options, flags };
};

/**
 * The bridge variables a child was spawned with, projected for exact assertions.
 *
 * @param env - Environment handed to the fake `spawn`.
 * @returns The six bridge names mapped to the values the child would see.
 */
const bridgeOf = (env) =>
  Object.fromEntries(
    [
      "PI_SUBAGENT_ORCHESTRATOR_TARGET",
      "PI_SUBAGENT_ORCHESTRATOR_SESSION_ID",
      "PI_SUBAGENT_RUN_ID",
      "PI_SUBAGENT_CHILD_AGENT",
      "PI_SUBAGENT_CHILD_INDEX",
      "PI_SUBAGENT_INTERCOM_SESSION_NAME",
    ].map((name) => [name, env[name]]),
  );

/**
 * The commands the extension wrote to a fake child's stdin.
 *
 * @param child - Fake child created by `spawn`.
 * @returns One parsed RPC command per written line.
 */
const childCommands = (child) =>
  child.stdin.writes.map((line) => JSON.parse(line));

/** Forget the children created by an earlier test. */
function resetChildren() {
  children.length = 0;
}

/**
 * Keep the SIGTERM-to-SIGKILL escalation short for one test, and restore it
 * afterwards so no other test inherits the shortened grace.
 *
 * @param t - Node test context, used to restore the previous value.
 */
function shortKillGrace(t) {
  const grace = process.env.SUBAGENT_KILL_GRACE_MS;
  process.env.SUBAGENT_KILL_GRACE_MS = "20";
  t.after(() => {
    if (grace === undefined) delete process.env.SUBAGENT_KILL_GRACE_MS;
    else process.env.SUBAGENT_KILL_GRACE_MS = grace;
  });
}

/**
 * Shorten the run-start deadline for one test.
 *
 * @param t - Node test context, used to restore the previous value.
 */
function shortStartDeadline(t) {
  const deadline = process.env.SUBAGENT_START_TIMEOUT_MS;
  process.env.SUBAGENT_START_TIMEOUT_MS = "50";
  t.after(() => {
    if (deadline === undefined) delete process.env.SUBAGENT_START_TIMEOUT_MS;
    else process.env.SUBAGENT_START_TIMEOUT_MS = deadline;
  });
}

/**
 * Control `Date.now` for one test, so status durations are exact.
 *
 * The returned function moves the clock forward by whole seconds. The real
 * clock is restored when the test ends.
 *
 * @param t - Node test context, used to restore the real clock.
 * @returns A function that advances the fake clock.
 */
function fakeClock(t) {
  const realNow = Date.now;
  let now = realNow();
  Date.now = () => now;
  t.after(() => {
    Date.now = realNow;
  });
  return (seconds) => {
    now += seconds * 1000;
  };
}

/**
 * Process environment a test owns, so the runner's own state cannot leak in.
 *
 * The suite may be run from a session that is itself on intercom, or from a
 * shell inside a spawned child.
 */
const OWNED_ENV = [
  "PI_INTERCOM_SESSION_ID",
  "PI_SUBAGENT_CHILD",
  "PI_SUBAGENT_TIMEOUT_SEC",
];

/**
 * Install a fresh extension instance against a fake `pi`.
 *
 * @param t - Node test context.
 * @param idle - Idle check reported by the fake context.
 * @param model - Model the fake context reports as the session's selection.
 * @param thinkingLevel - Thinking level the fake context reports.
 * @param intercom - Intercom id and session name to appear connected as.
 * @returns The fake pi, the registered tool, and a `call` helper.
 */
function setup(
  t,
  { idle = () => true, model, thinkingLevel, intercom } = {},
) {
  resetChildren();
  shortKillGrace(t);
  const previous = new Map(
    OWNED_ENV.filter((name) => name in process.env).map((name) => [
      name,
      process.env[name],
    ]),
  );
  for (const name of OWNED_ENV) delete process.env[name];
  if (intercom !== undefined) {
    process.env.PI_INTERCOM_SESSION_ID = intercom.id;
  }
  t.after(() => {
    for (const name of OWNED_ENV) delete process.env[name];
    for (const [name, value] of previous) process.env[name] = value;
  });
  const pi = fakePi(intercom?.name);
  installSubagent(pi.api);
  const tool = pi.tools.get("subagent");
  const ctx = { cwd: workDir, isIdle: idle, model, thinkingLevel };
  return {
    pi,
    tool,
    children,
    call: (params) => tool.execute("call", params, undefined, undefined, ctx),
  };
}

/**
 * Wait until `count` notifications have been sent.
 *
 * @param pi - Fake pi holding the sent messages.
 * @param count - Number of notifications to wait for.
 * @returns The sent notifications.
 */
async function notices(pi, count = 1) {
  await waitFor(() => pi.sent.length >= count);
  return pi.sent;
}

describe("subagent", () => {
  describe("the call contract", () => {
    test("rejects an empty id, a live duplicate, and a non-directory cwd", async (t) => {
      const { call } = setup(t);
      assert.match((await call({ id: "", prompt: "x" })).content[0].text, /must not be empty/);
      assert.match((await call({ id: "dup", prompt: "x" })).content[0].text, /started/);
      assert.match((await call({ id: "dup", prompt: "x" })).content[0].text, /already running/);
      const bad = await call({ id: "bad", prompt: "x", cwd: "/etc/hosts" });
      assert.match(bad.content[0].text, /not a directory/);
    });

    test("rejects a timeout that could never elapse", async (t) => {
      const { call, children } = setup(t);
      assert.match(
        (await call({ id: "bad-timeout", prompt: "x", timeoutSec: 0 })).content[0].text,
        /positive number of seconds/,
      );
      assert.match(
        (await call({ id: "bad-timeout", prompt: "x", timeoutSec: -5 })).content[0].text,
        /positive number of seconds/,
      );
      assert.match(
        (await call({ id: "bad-timeout", prompt: "x", timeoutSec: 1e9 })).content[0].text,
        /at most \d+s/,
        "a limit setTimeout cannot hold would fire at once instead",
      );
      assert.equal(children.length, 0, "an unusable timeout spawns nothing");
    });

    test("defaults the timeout and reports the deadline it got", async (t) => {
      const { call, pi, children } = setup(t);
      const result = await call({ id: "default-timeout", prompt: "x" });
      assert.match(
        result.content[0].text,
        new RegExp(`timeout=${DEFAULT_TIMEOUT_SEC}s`),
      );
      const status = await pi.tools
        .get("subagent_status")
        .execute("call", { id: "default-timeout" }, undefined, undefined, {});
      assert.match(
        status.content[0].text,
        new RegExp(`timeout=${DEFAULT_TIMEOUT_SEC}s`),
      );
      const customResult = await call({
        id: "custom-timeout",
        prompt: "x",
        timeoutSec: 90,
      });
      assert.match(customResult.content[0].text, /timeout=90s/);
      assert.match(
        childOptions(children.at(-1)).options["append-system-prompt"],
        /This session has a 90s wall-clock limit/,
        "the child is told the same deadline the parent reports",
      );
      assert.deepEqual(childCommands(children.at(-1)), [
        { id: "prompt", type: "prompt", message: "Task: x" },
      ]);
      await pi.hooks.get("session_shutdown")({ reason: "quit" });
      assert.ok(children.length >= 1);
    });

    test("a fresh extension instance starts with no subagents", async (t) => {
      const { call, pi, children } = setup(t, { idle: () => false });
      await call({ id: "reuse", prompt: "x" });
      children[0].close(0);
      await new Promise((resolve) => setTimeout(resolve, 20));
      await pi.hooks.get("session_shutdown")({ reason: "quit" });
      // A new instance starts with no memory of the old one, so the same id works.
      const { call: freshCall, pi: freshPi, children: freshChildren } = setup(t);
      const result = await freshCall({ id: "reuse", prompt: "x" });
      assert.match(result.content[0].text, /started/);
      freshChildren[0].write(assistantRecord("second try"));
      freshChildren[0].close(0);
      const [sent] = await notices(freshPi);
      assert.match(sent.message.content, /second try/);
    });
  });

  describe("the child invocation", () => {
    test("builds the child invocation from the call", async (t) => {
      const { call, children } = setup(t);
      await call({ id: "cfg", prompt: "do it", model: "some/model", tools: ["read", "bash"] });
      const [child] = children;
      assert.equal(child.options.cwd, workDir);
      assert.equal(child.options.shell, false);
      const { options, flags } = childOptions(child);
      assert.equal(
        options.name,
        "cfg",
        "the child's session is named after the call's id, so peers can address it",
      );
      assert.equal(options.mode, "rpc", "the child stays alive between its turns");
      assert.ok(flags.has("no-session"), "the child keeps no session file of its own");
      assert.equal(options.model, "some/model");
      assert.deepEqual(
        options.tools.split(","),
        ["read", "bash", "subagent_finish"],
        "the child gets the allowed tools plus its own way to end the session",
      );
      assert.ok(
        flags.has("append-system-prompt"),
        "the child's role and deadline live in an appended system prompt",
      );
      assert.match(options["append-system-prompt"], /You are a subagent/);
      assert.match(
        options["append-system-prompt"],
        new RegExp(`${DEFAULT_TIMEOUT_SEC}s wall-clock limit`),
        "the child is told the deadline it runs under",
      );
      assert.ok(
        !child.args.some((arg) => arg.startsWith("Task: do it")),
        "the prompt travels on stdin, not in argv",
      );
      assert.deepEqual(childCommands(child), [
        { id: "prompt", type: "prompt", message: "Task: do it" },
      ]);
      assert.equal(
        child.options.env.PI_SUBAGENT_CHILD,
        "1",
        "the child is told to end itself when its work is done",
      );
      assert.equal(
        child.options.env.PI_SUBAGENT_TIMEOUT_SEC,
        String(DEFAULT_TIMEOUT_SEC),
        "the child warns itself against the same deadline",
      );
      assert.equal(child.command, process.argv[1], "the child reuses the running pi build");
    });

    test("lets PI_BIN override the child command", async (t) => {
      const previous = process.env.PI_BIN;
      process.env.PI_BIN = "/opt/other/pi";
      t.after(() => {
        if (previous === undefined) delete process.env.PI_BIN;
        else process.env.PI_BIN = previous;
      });
      const { call, children } = setup(t);
      await call({ id: "bin", prompt: "x" });
      assert.equal(children[0].command, "/opt/other/pi");
    });

    test("keeps pi's defaults when model and tools are omitted", async (t) => {
      const { call, children } = setup(t);
      await call({ id: "plain", prompt: "x" });
      const { options } = childOptions(children[0]);
      assert.equal(options.model, undefined);
      assert.equal(options.tools, undefined);
    });

    test("keeps the finish tool reachable whatever the caller selected", async (t) => {
      const { call, children, pi } = setup(t);
      const toolsOf = async (tools) => {
        await call({ id: `sel-${tools.join("_")}`, prompt: "x", tools });
        return childOptions(children.at(-1)).options.tools;
      };

      assert.equal(await toolsOf(["read"]), "read,subagent_finish");
      assert.equal(await toolsOf(["read", "subagent_finish"]), "read,subagent_finish");
      assert.equal(await toolsOf(["+codemode"]), "+codemode", "a modifier list is left alone");
      assert.equal(
        await toolsOf(["+codemode", "-subagent_finish"]),
        "+codemode,+subagent_finish",
        "an explicit removal is undone",
      );
      await pi.tools.get("subagent_kill").execute("call", {}, undefined, undefined, {});
    });

    test("tells the child which session spawned it", async (t) => {
      const { call, children } = setup(t, {
        intercom: { id: "01a1cf7a-ccf2-72dc-830f", name: "planner" },
      });
      await call({ id: "probe", prompt: "x", tools: ["read"] });
      await call({ id: "second", prompt: "x" });
      assert.deepEqual(bridgeOf(children[0].options.env), {
        PI_SUBAGENT_ORCHESTRATOR_TARGET: "planner",
        PI_SUBAGENT_ORCHESTRATOR_SESSION_ID: "01a1cf7a-ccf2-72dc-830f",
        PI_SUBAGENT_RUN_ID: "probe",
        PI_SUBAGENT_CHILD_AGENT: "probe",
        PI_SUBAGENT_CHILD_INDEX: "1",
        PI_SUBAGENT_INTERCOM_SESSION_NAME: "probe",
      });
      assert.equal(
        bridgeOf(children[1].options.env).PI_SUBAGENT_CHILD_INDEX,
        "2",
        "each child carries its own place in this session's start order",
      );
      assert.equal(
        childOptions(children[0]).options.tools,
        "read,subagent_finish",
        "the extension adds no tool of another extension to the selection",
      );
      assert.equal(
        children[0].options.env.PI_SUBAGENT_SUPERVISOR_CHANNEL_DIR,
        undefined,
        "the child inherits no channel from an outer run",
      );
    });

    test("targets an unnamed session by its id", async (t) => {
      const { call, children } = setup(t, {
        intercom: { id: "01a1cf7a-ccf2-72dc-830f" },
      });
      await call({ id: "probe", prompt: "x" });
      assert.equal(
        children[0].options.env.PI_SUBAGENT_ORCHESTRATOR_TARGET,
        "01a1cf7a-ccf2-72dc-830f",
      );
    });

    test("carries no bridge when this session is not on intercom", async (t) => {
      const { call, children } = setup(t);
      await call({ id: "plain", prompt: "x" });
      assert.deepEqual(bridgeOf(children[0].options.env), {
        PI_SUBAGENT_ORCHESTRATOR_TARGET: undefined,
        PI_SUBAGENT_ORCHESTRATOR_SESSION_ID: undefined,
        PI_SUBAGENT_RUN_ID: undefined,
        PI_SUBAGENT_CHILD_AGENT: undefined,
        PI_SUBAGENT_CHILD_INDEX: undefined,
        PI_SUBAGENT_INTERCOM_SESSION_NAME: undefined,
      });
    });

    test("a child belongs to the session that spawned it, not the run above", async (t) => {
      const stale = {
        PI_INTERCOM_SESSION_ID: "grandparent-id",
        PI_SUBAGENT_SUPERVISOR_CHANNEL_DIR: "/tmp/channel",
        PI_SUBAGENT_ORCHESTRATOR_TARGET: "grandparent",
        PI_SUBAGENT_ORCHESTRATOR_SESSION_ID: "grandparent-id",
        PI_SUBAGENT_RUN_ID: "outer-run",
        PI_SUBAGENT_CHILD_AGENT: "outer-agent",
        PI_SUBAGENT_CHILD_INDEX: "9",
        PI_SUBAGENT_INTERCOM_SESSION_NAME: "outer-child",
      };
      const previous = new Map(
        Object.keys(stale)
          .filter((name) => name in process.env)
          .map((name) => [name, process.env[name]]),
      );
      Object.assign(process.env, stale);
      t.after(() => {
        for (const name of Object.keys(stale)) delete process.env[name];
        for (const [name, value] of previous) process.env[name] = value;
      });

      const { call, children } = setup(t);
      await call({ id: "plain", prompt: "x" });
      const absent = {
        PI_SUBAGENT_ORCHESTRATOR_TARGET: undefined,
        PI_SUBAGENT_ORCHESTRATOR_SESSION_ID: undefined,
        PI_SUBAGENT_RUN_ID: undefined,
        PI_SUBAGENT_CHILD_AGENT: undefined,
        PI_SUBAGENT_CHILD_INDEX: undefined,
        PI_SUBAGENT_INTERCOM_SESSION_NAME: undefined,
      };
      assert.deepEqual(bridgeOf(children[0].options.env), absent);
      assert.equal(children[0].options.env.PI_INTERCOM_SESSION_ID, undefined);
      assert.equal(
        children[0].options.env.PI_SUBAGENT_SUPERVISOR_CHANNEL_DIR,
        undefined,
      );

      // The same session, now on intercom, hands its child a bridge to itself:
      // never the target it inherited, and never its own id as the child's.
      process.env.PI_INTERCOM_SESSION_ID = "own-id";
      await call({ id: "bridged", prompt: "x" });
      assert.deepEqual(bridgeOf(children[1].options.env), {
        PI_SUBAGENT_ORCHESTRATOR_TARGET: "own-id",
        PI_SUBAGENT_ORCHESTRATOR_SESSION_ID: "own-id",
        PI_SUBAGENT_RUN_ID: "bridged",
        PI_SUBAGENT_CHILD_AGENT: "bridged",
        PI_SUBAGENT_CHILD_INDEX: "2",
        PI_SUBAGENT_INTERCOM_SESSION_NAME: "bridged",
      });
      assert.equal(children[1].options.env.PI_INTERCOM_SESSION_ID, undefined);
    });

    test("inherits the session's model and thinking level", async (t) => {
      const { call, children } = setup(t, {
        model: { provider: "qoder", id: "Fast" },
        thinkingLevel: "high",
      });
      const result = await call({ id: "inherit", prompt: "x" });
      const [child] = children;
      const { options } = childOptions(child);
      assert.equal(options.model, "qoder/Fast");
      assert.equal(options.thinking, "high");
      assert.match(result.content[0].text, /model=qoder\/Fast/);
    });

    test("an explicit model wins over the session's selection", async (t) => {
      const { call, children } = setup(t, {
        model: { provider: "qoder", id: "Fast" },
        thinkingLevel: "high",
      });
      await call({ id: "explicit", prompt: "x", model: "some/model:low" });
      const { options, flags } = childOptions(children[0]);
      assert.equal(options.model, "some/model:low");
      assert.ok(
        !flags.has("thinking"),
        "a `:level` suffix already carries the level",
      );
    });
  });

  describe("reading the child's output", () => {
    test("splits JSONL records across chunk boundaries", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "chunks", prompt: "x" });
      const record = assistantRecord("split answer");
      for (const char of record) children[0].write(char);
      children[0].write("\n");
      children[0].close(0);
      const [sent] = await notices(pi);
      assert.match(sent.message.content, /split answer/);
    });

    test("keeps only the last assistant answer", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "last", prompt: "x" });
      children[0].write(assistantRecord("first"));
      children[0].write(assistantRecord("second"));
      children[0].close(0);
      const [sent] = await notices(pi);
      assert.match(sent.message.content, /second/);
      assert.doesNotMatch(sent.message.content, /first/);
    });

    test("a finish call's answer outranks the sign-off after it", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "report", prompt: "x" });
      children[0].write(assistantRecord("the full report"));
      children[0].write(finishRecord("REPORT"));
      children[0].write(assistantRecord("The review is above."));
      children[0].close(0);
      const [sent] = await notices(pi);
      assert.match(sent.message.content, /^\[subagent report\] finished in \d+s\./);
      assert.match(sent.message.content, /REPORT/);
      assert.doesNotMatch(sent.message.content, /The review is above\./);
    });

    test("an answer-only finish call still reports the answer", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "bare", prompt: "x" });
      children[0].write(finishRecord("REPORT"));
      children[0].close(0);
      const [sent] = await notices(pi);
      assert.match(sent.message.content, /^\[subagent bare\] finished in \d+s\./);
      assert.match(sent.message.content, /REPORT/);
    });

    test("a child that exits without an answer is reported as a failure", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "silent", prompt: "x" });
      children[0].close(0);
      const [sent] = await notices(pi);
      assert.match(sent.message.content, /^\[subagent silent\] failed after \d+s: /);
      assert.match(sent.message.content, /exited without an answer/);
    });

    test("a malformed record alone does not pass as success", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "garbled", prompt: "x" });
      children[0].write('{"type":"message_end","message":}\n');
      children[0].close(0);
      const [sent] = await notices(pi);
      assert.match(sent.message.content, /\[subagent garbled\] failed after/);
    });

    test("an oversized record is dropped and the next record in the chunk is read", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "relay", prompt: "x" });
      // One record past the cap, then a complete answer in the same chunk.
      children[0].write(
        `${"x".repeat(MAX_RECORD_BYTES + 1)}\n${assistantRecord("after the big one")}`,
      );
      children[0].close(0);
      const [sent] = await notices(pi);
      assert.match(sent.message.content, /finished in/);
      assert.match(sent.message.content, /after the big one/);
    });

    test("classifies exit codes, signals, and JSON-mode stop reasons", async (t) => {
      const cases = [
        { record: assistantRecord("a"), close: [3, null], expect: /exit code 3/ },
        { record: assistantRecord("a"), close: [null, "SIGTERM"], expect: /signal SIGTERM/ },
        {
          record: assistantRecord("a", { stopReason: "error", errorMessage: "boom" }),
          close: [0, null],
          expect: /boom/,
        },
        {
          record: assistantRecord("a", { stopReason: "length" }),
          close: [0, null],
          expect: /the child stopped: length/,
        },
      ];
      for (const { record, close, expect } of cases) {
        const { call, pi, children } = setup(t);
        await call({ id: "case", prompt: "x" });
        children[0].write(record);
        children[0].close(...close);
        const [sent] = await notices(pi);
        assert.match(sent.message.content, /failed after/);
        assert.match(sent.message.content, expect);
      }
    });

    test("a child that outlives its timeout is stopped and reported as timed out", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "stuck", prompt: "x", timeoutSec: 0.05 });
      const [child] = children;

      const [sent] = await notices(pi);
      assert.match(
        sent.message.content,
        /^\[subagent stuck\] timeout after \d+s: no result within its 0.05s timeout/,
      );
      assert.ok(child.kills.includes("SIGTERM"), "the child is stopped, not left running");
      assert.ok(
        await waitFor(() => child.kills.includes("SIGKILL")),
        "a child that ignores SIGTERM is escalated",
      );
      assert.equal(pi.sent.length, 1, "the timeout reports once");
      const status = await pi.tools
        .get("subagent_status")
        .execute("call", { id: "stuck" }, undefined, undefined, {});
      assert.match(status.content[0].text, /\[subagent stuck\] timeout after \d+s/);
    });

    test("a child that finishes before its timeout is not stopped", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "quick", prompt: "x", timeoutSec: 0.05 });
      children[0].write(assistantRecord("in time"));
      children[0].close(0);
      const [sent] = await notices(pi);
      assert.match(sent.message.content, /finished in \d+s\./);
      await new Promise((resolve) => setTimeout(resolve, 80));
      assert.deepEqual(children[0].kills, [], "the deadline is cleared on result");
    });

    test("a spawn failure is reported once", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "enoent", prompt: "x" });
      children[0].fail("spawn pi ENOENT");
      children[0].close(-2);
      const sent = await notices(pi);
      assert.equal(sent.length, 1, "error and close do not both report");
      assert.match(sent[0].message.content, /spawn error: spawn pi ENOENT/);
    });
  });

  describe("the RPC conversation with the child", () => {
    test("cancels every extension UI record the child cannot show anyone", async (t) => {
      const { call, children } = setup(t);
      await call({ id: "dialog", prompt: "x" });
      const [child] = children;
      child.write(
        rpcRecord({
          type: "extension_ui_request",
          id: "ui-1",
          method: "confirm",
          title: "Allow dangerous command?",
          message: "rm -rf /",
        }),
      );
      child.write(
        rpcRecord({ type: "extension_ui_request", id: "ui-2", method: "notify", message: "hi" }),
      );
      const answers = childCommands(child).filter((command) => command.type === "extension_ui_response");
      assert.deepEqual(answers, [
        { type: "extension_ui_response", id: "ui-1", cancelled: true },
        // Harmless: pi ignores a response to a fire-and-forget record, and a new
        // blocking method must not leave the child waiting.
        { type: "extension_ui_response", id: "ui-2", cancelled: true },
      ]);
    });

    test("a prompt the child refuses ends the call with that reason", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "refused", prompt: "x" });
      children[0].write(
        rpcRecord({ id: "prompt", type: "response", command: "prompt", success: false, error: "Model not found" }),
      );
      children[0].close(143);
      const [sent] = await notices(pi);
      assert.match(sent.message.content, /^\[subagent refused\] failed after \d+s: Model not found/);
      assert.ok(
        children[0].kills.includes("SIGTERM"),
        "a child that never ran is stopped instead of left waiting",
      );
    });

    test("a prompt an extension consumes counts as a failure, not a silent wait", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "consumed", prompt: "x" });
      children[0].write(
        rpcRecord({
          id: "prompt",
          type: "response",
          command: "prompt",
          success: true,
          data: { disposition: "handled" },
        }),
      );
      children[0].close(143);
      const [sent] = await notices(pi);
      assert.match(sent.message.content, /failed after \d+s: the child handed its prompt/);
    });

    test("a child that never starts a run is stopped at the deadline", async (t) => {
      shortStartDeadline(t);
      const { call, pi, children } = setup(t);
      await call({ id: "silent-start", prompt: "x" });
      const [sent] = await notices(pi);
      assert.match(sent.message.content, /failed after \d+s: the child never started a run/);
      assert.ok(children[0].kills.includes("SIGTERM"));
    });

    test("a started run disarms the deadline", async (t) => {
      shortStartDeadline(t);
      const { call, pi, children } = setup(t);
      await call({ id: "starting", prompt: "x" });
      children[0].write(rpcRecord({ type: "agent_start" }));
      await new Promise((resolve) => setTimeout(resolve, 120));
      assert.deepEqual(children[0].kills, [], "a run that started is left alone");
      children[0].write(assistantRecord("done"));
      children[0].close(0);
      const [sent] = await notices(pi);
      assert.match(sent.message.content, /finished in/);
    });

    test("an extension failure in the child reaches the failure text", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "broken", prompt: "x" });
      children[0].write(
        rpcRecord({
          type: "extension_error",
          extensionPath: "/ext/bad.ts",
          event: "agent_settled",
          error: "boom",
        }),
      );
      children[0].close(1);
      const [sent] = await notices(pi);
      assert.match(sent.message.content, /extension error in \/ext\/bad\.ts on agent_settled: boom/);
    });
  });

  describe("delivering the result", () => {
    test("returns before the child finishes and reports it once", async (t) => {
      const { call, pi, children } = setup(t);
      const result = await call({ id: "slow", prompt: "x" });
      assert.match(result.content[0].text, /Subagent "slow" started/);
      assert.equal(pi.sent.length, 0, "nothing is sent until the child exits");

      children[0].write(assistantRecord("PONG"));
      children[0].close(0);
      const [sent] = await notices(pi);
      assert.match(sent.message.content, /^\[subagent slow\] finished in \d+s\./);
      assert.match(sent.message.content, /PONG/);
      assert.deepEqual(sent.options, { deliverAs: "steer", triggerTurn: true });
    });

    test("queues a result immediately while the parent remains busy", async (t) => {
      const { call, pi, children } = setup(t, {
        idle: () => {
          throw new Error("child callbacks must not retain ctx");
        },
      });
      await call({ id: "busy", prompt: "x" });
      children[0].write(assistantRecord("ready"));
      children[0].close(0);
      assert.equal(pi.sent.length, 1, "delivery does not wait for idle or a poll");
      assert.match(pi.sent[0].message.content, /ready/);
      assert.deepEqual(pi.sent[0].options, { deliverAs: "steer", triggerTurn: true });
      const kill = await pi.tools.get("subagent_kill").execute("call", { id: "busy" });
      assert.match(kill.content[0].text, /No running subagent/);
      assert.deepEqual(children[0].kills, [], "an exited child cannot be killed");
      assert.equal(pi.sent.length, 1);
    });
  });

  describe("the /subagents view", () => {
    /**
     * A fake extension UI that opens a custom component like the TUI mode does.
     *
     * @param t - Node test context, used to dispose a component left open.
     * @param bindings - User keybindings, as `keybindings.json` holds them.
     * @param rows - Terminal height the component sees; tall enough to fit the
     *   whole box unless a test asks for a short terminal.
     * @returns The fake UI, its notifications, and the open component.
     */
    function fakeUI(t, bindings = {}, rows = 40) {
      const notified = [];
      let component;
      const tui = { requestRender() {}, terminal: { rows } };
      const theme = { fg: (_color, text) => text, bold: (text) => text };
      t.after(() => component?.dispose?.());
      return {
        notified,
        get component() {
          return component;
        },
        ui: {
          notify: (text) => notified.push(text),
          custom(factory) {
            return new Promise((resolve) => {
              const done = (result) => {
                const closing = component;
                component = undefined;
                closing?.dispose?.();
                resolve(result);
              };
              const keybindings = new KeybindingsManager(
                TUI_KEYBINDINGS,
                bindings,
              );
              component = factory(tui, theme, keybindings, done);
            });
          },
        },
      };
    }

    /**
     * A rendered line without its ANSI attributes.
     *
     * @param line - Rendered widget line.
     * @returns The text the user sees.
     */
    function plainOf(line) {
      return line.replace(/\x1b\[[0-9;]*m/g, "");
    }

    /**
     * Visible width of a rendered line without its ANSI attributes.
     *
     * @param line - Rendered widget line.
     * @returns Number of terminal columns it occupies.
     */
    function widthOf(line) {
      return plainOf(line).length;
    }

    /** Spinner frame or finished-state glyph of a row's state marker. */
    const STATE_MARKER = /[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏✓✗⧖·]/;

    test("/subagents lists running children and says when there are none", async (t) => {
      const { call, pi } = setup(t);
      const command = pi.commands.get("subagents");
      const notified = [];
      const ctx = { ui: { notify: (text) => notified.push(text) } };
      await command.handler("", ctx);
      assert.deepEqual(notified, ["No subagents have run in this session."]);

      await call({ id: "listed", prompt: "x", model: "m", tools: ["read"] });
      notified.length = 0;
      await command.handler("", ctx);
      assert.equal(
        notified[0],
        `[subagent listed] running for 0s (m, tools=read, ${workDir}, timeout=${DEFAULT_TIMEOUT_SEC}s)`,
      );
    });

    test("/subagents shows a live overlay that closes on Escape", async (t) => {
      const { call, pi, children } = setup(t);
      const screen = fakeUI(t);
      const command = pi.commands.get("subagents");
      const ctx = { mode: "tui", ui: screen.ui };

      const showing = command.handler("", ctx);
      const overlay = screen.component;
      assert.ok(overlay, "the command opens the overlay");
      const empty = overlay.render(60).join("\n");
      assert.match(empty, /Subagents/);
      assert.match(empty, /No subagents have run/);
      assert.match(empty, /Press Escape to close/);

      await call({ id: "first", prompt: "x", model: "m", tools: ["read"] });
      await call({ id: "second", prompt: "y" });
      // The first child finishes while the second keeps running; creation order
      // still decides the row order.
      children[0].write(assistantRecord("first done"));
      children[0].close(0);

      const lines = overlay.render(160);
      const text = lines.join("\n");
      assert.match(text, /1 running, 1 finished/);
      assert.ok(text.indexOf("first") < text.indexOf("second"));
      assert.match(text, /second +[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] +running +0s/);

      // Every row starts its tools and cwd columns at the same offset.
      const firstRow = lines.find((line) => line.includes(" first "));
      const secondRow = lines.find((line) => line.includes(" second "));
      assert.ok(firstRow && secondRow, "both subagents are listed");
      assert.match(firstRow, / first +\S +done /);
      // The state marker follows the id: a glyph once the child ended, the
      // spinner while it runs, so it never sits beside the selection cursor.
      for (const [row, id] of [
        [firstRow, "first"],
        [secondRow, "second"],
      ]) {
        assert.ok(
          plainOf(row).indexOf(id) < plainOf(row).search(STATE_MARKER),
          `the row names ${id} before its state marker`,
        );
      }
      assert.doesNotMatch(
        plainOf(firstRow),
        new RegExp(`${SELECTED_CURSOR} *${STATE_MARKER.source}`),
        "the cursor is not immediately followed by the state marker",
      );
      // The status column is right-aligned, so both words end at one offset.
      assert.equal(
        firstRow.indexOf("done") + "done".length,
        secondRow.indexOf("running") + "running".length,
        "status column is aligned",
      );
      assert.equal(
        firstRow.indexOf("0s"),
        secondRow.indexOf("0s"),
        "elapsed column is aligned",
      );
      // A finished row keeps the deadline it had, so both rows show a timeout.
      assert.match(firstRow, new RegExp(`timeout=${DEFAULT_TIMEOUT_SEC}s`));
      assert.match(secondRow, new RegExp(`timeout=${DEFAULT_TIMEOUT_SEC}s`));
      assert.equal(
        firstRow.indexOf("timeout="),
        secondRow.indexOf("timeout="),
        "timeout column is aligned",
      );
      assert.equal(
        firstRow.indexOf("tools="),
        secondRow.indexOf("tools="),
        "tools column is aligned",
      );
      assert.equal(
        firstRow.indexOf(workDir),
        secondRow.indexOf(workDir),
        "cwd column is aligned",
      );

      // A narrow terminal cuts the row instead of overflowing it.
      const narrow = overlay.render(40);
      for (const line of narrow) assert.equal(widthOf(line), 40);

      overlay.handleInput("\x1b");
      await showing;
      assert.equal(screen.component, undefined, "Escape closes the overlay");

      await pi.hooks.get("session_shutdown")({ reason: "quit" });
    });

    test("/subagents opens the selected child's details and Escape walks back", async (t) => {
      const { call, pi, children } = setup(t);
      const screen = fakeUI(t);
      const command = pi.commands.get("subagents");
      const ctx = { mode: "tui", ui: screen.ui };

      const showing = command.handler("", ctx);
      const overlay = screen.component;
      await call({ id: "alpha", prompt: "x" });
      await call({ id: "beta", prompt: "y", model: "beta-model" });
      children[1].write(updateRecord({ type: "text_start", contentIndex: 0 }));
      children[1].write(
        updateRecord({
          type: "text_delta",
          contentIndex: 0,
          delta: "Checking",
        }),
      );
      children[1].write(
        updateRecord({
          type: "text_delta",
          contentIndex: 0,
          delta: " the build.\nAlmost done",
        }),
      );
      // Further deltas of the same block must not become another step.
      children[1].write(
        updateRecord({ type: "text_delta", contentIndex: 0, delta: " here" }),
      );

      const list = overlay.render(120).join("\n");
      assert.match(list, /Enter for details, Escape to close/);
      assert.match(list, /alpha/);

      // The first row starts selected; down moves the cursor to the second.
      const selectedRow = (lines) =>
        lines
          .find((line) => line.trimStart().startsWith(`${SELECTED_CURSOR} `))
          ?.match(/\b(alpha|beta)\b/)?.[1];
      assert.equal(selectedRow(overlay.render(120)), "alpha");
      overlay.handleInput("\x1b[B");
      assert.equal(selectedRow(overlay.render(120)), "beta");
      overlay.handleInput("\r");
      const detail = overlay.render(120).join("\n");
      assert.match(detail, /beta/);
      assert.match(detail, /running for \d+s/);
      assert.match(detail, /beta-model/);
      assert.match(detail, /\btext\s+Checking the build\./);
      assert.match(detail, /writing/);
      // Every line is stamped with the local time, the spawn first.
      const stamped = detail
        .split("\n")
        .map((line) => line.trim().match(/^\d\d:\d\d:\d\d (\S+)/)?.[1])
        .filter(Boolean);
      assert.deepEqual(stamped, ["start", "text"]);
      // One blank line separates the settings from the pinned spawn line, and
      // the steps follow it directly.
      const rows = detail.split("\n").map((line) => line.trim());
      const spawn = rows.findIndex((line) => /^\d\d:\d\d:\d\d start$/.test(line));
      assert.ok(spawn > 0, "the spawn line is rendered");
      assert.equal(rows[spawn - 1], "", "a blank line follows the settings");
      assert.match(rows[spawn + 1], /^\d\d:\d\d:\d\d text\b/);
      assert.doesNotMatch(detail, /alpha/);
      assert.equal(
        detail.split("\n").filter((line) => /\btext\b/.test(line)).length,
        1,
        "one streamed block is one step",
      );
      assert.match(detail, /Escape to go back/);

      overlay.handleInput("\x1b");
      const back = overlay.render(120).join("\n");
      assert.match(back, /Enter for details, Escape to close/);
      assert.doesNotMatch(back, /Escape to go back/);

      // A child that has done nothing yet still pins its spawn line above the
      // empty state.
      overlay.handleInput("\x1b[A");
      overlay.handleInput("\r");
      const idle = overlay.render(120).join("\n");
      assert.match(idle, /\d\d:\d\d:\d\d start/);
      assert.match(idle, /No activity yet\./);
      overlay.handleInput("\x1b");

      overlay.handleInput("\x1b");
      await showing;
      assert.equal(screen.component, undefined, "Escape from the list closes");
      await pi.hooks.get("session_shutdown")({ reason: "quit" });
    });

    test("/subagents details repeat the row's model, tools, cwd and timeout", async (t) => {
      const { call, pi } = setup(t);
      const screen = fakeUI(t);
      const showing = pi.commands
        .get("subagents")
        .handler("", { mode: "tui", ui: screen.ui });
      const overlay = screen.component;

      await call({
        id: "audited",
        prompt: "x",
        model: "audit-model",
        tools: ["read", "bash"],
        timeoutSec: 90,
      });
      overlay.handleInput("\r");
      const detail = overlay.render(160).join("\n");
      const header = detail.split("\n").find((line) => line.includes("audited"));

      assert.ok(header, "the detail view names the child");
      assert.ok(
        header.indexOf("audited") < header.indexOf("running"),
        "the id comes before the state",
      );
      assert.ok(
        plainOf(header).indexOf("audited") <
          plainOf(header).search(STATE_MARKER),
        "the header names the child before its state marker",
      );
      assert.match(header, /running for \d+s/);
      assert.match(header, /audit-model/);
      assert.match(header, /tools=read,bash/);
      assert.ok(
        header.includes(workDir),
        "the header shows the working directory",
      );
      assert.match(header, /timeout=90s/);
      // The header repeats the row's settings in the list's column order.
      const settings = ["timeout=90s", "audit-model", "tools=read,bash", workDir];
      const offsets = settings.map((text) => header.indexOf(text));
      assert.deepEqual(
        offsets,
        [...offsets].sort((a, b) => a - b),
        "timeout, model, tools and cwd keep the list row's order",
      );

      overlay.handleInput("\x1b");
      overlay.handleInput("\x1b");
      await showing;
      await pi.hooks.get("session_shutdown")({ reason: "quit" });
    });

    test("/subagents moves its selection with the user's list keys", async (t) => {
      const { call, pi } = setup(t);
      const screen = fakeUI(t, {
        "tui.select.up": ["up", "ctrl+p"],
        "tui.select.down": ["down", "ctrl+n"],
      });
      const showing = pi.commands
        .get("subagents")
        .handler("", { mode: "tui", ui: screen.ui });
      const overlay = screen.component;
      await call({ id: "alpha", prompt: "x" });
      await call({ id: "beta", prompt: "y" });
      const selectedRow = () =>
        overlay
          .render(120)
          .find((line) => line.trimStart().startsWith(`${SELECTED_CURSOR} `))
          ?.match(/\b(alpha|beta)\b/)?.[1];

      overlay.handleInput("\x0e"); // ctrl+n
      assert.equal(selectedRow(), "beta");
      overlay.handleInput("\x10"); // ctrl+p
      assert.equal(selectedRow(), "alpha");

      overlay.handleInput("\x1b");
      await showing;
      await pi.hooks.get("session_shutdown")({ reason: "quit" });
    });

    test("/subagents keeps a finished child's steps in its details", async (t) => {
      const { call, pi, children } = setup(t);
      const screen = fakeUI(t);
      const command = pi.commands.get("subagents");
      const showing = command.handler("", { mode: "tui", ui: screen.ui });
      const overlay = screen.component;

      await call({ id: "ended", prompt: "x" });
      children[0].write(
        updateRecord({ type: "thinking_start", contentIndex: 0 }),
      );
      children[0].write(
        updateRecord({
          type: "thinking_delta",
          contentIndex: 0,
          delta: "weighing the options",
        }),
      );
      children[0].write(
        updateRecord({
          type: "thinking_end",
          contentIndex: 0,
          content: "weighing the options",
        }),
      );
      children[0].write(
        toolRecord("tool_execution_start", "call-1", "read", {
          path: "src/auth.ts",
        }),
      );
      children[0].write(
        toolRecord("tool_execution_end", "call-1", "read"),
      );
      children[0].write(assistantRecord("all done"));
      children[0].close(0);
      await notices(pi);

      overlay.handleInput("\r");
      const detail = overlay.render(120).join("\n");
      assert.match(detail, /ended/);
      assert.match(detail, /done after \d+s/);
      assert.match(detail, /\bthink\s+\d+ chars/);
      assert.match(detail, /\bread\s+src\/auth\.ts/);
      assert.doesNotMatch(detail, /weighing the options/);
      assert.doesNotMatch(detail, /running \d+s/);
      assert.match(detail, /Escape to go back/);

      overlay.handleInput("\x1b");
      assert.match(
        overlay.render(120).join("\n"),
        /Enter for details, Escape to close/,
      );
      overlay.handleInput("\x1b");
      await showing;
      await pi.hooks.get("session_shutdown")({ reason: "quit" });
    });

    test("/subagents fits a short terminal and scrolls its details", async (t) => {
      const { call, pi, children } = setup(t);
      const rows = 20;
      const screen = fakeUI(t, {}, rows);
      const showing = pi.commands
        .get("subagents")
        .handler("", { mode: "tui", ui: screen.ui });
      const overlay = screen.component;

      await call({ id: "chatty", prompt: "x" });
      const steps = 12;
      for (let index = 0; index < steps; index += 1) {
        children[0].write(
          toolRecord(
            "tool_execution_start",
            `call-${index}`,
            `probe-${index}`,
            { path: `file-${index}.ts` },
          ),
        );
      }
      overlay.handleInput("\r");

      // The page must leave pi its own rows above and below, so the viewport
      // never clips the hint away. The fake UI cannot see pi's real rows, so a
      // page that grows past the reserve would clip in a real terminal.
      const detail = overlay.render(100);
      const text = detail.map(plainOf).join("\n");
      assert.ok(
        detail.length <= rows - VIEWPORT_RESERVE_ROWS,
        `page leaves pi its rows: ${detail.length} of ${rows}`,
      );
      assert.match(text, /Escape to go back/);
      assert.match(text, /\d\d:\d\d:\d\d start/, "the spawn line stays fixed");
      assert.match(text, /probe-11/, "the newest step stays in view");
      assert.doesNotMatch(text, /probe-0\b/, "older steps start out hidden");
      assert.match(
        text,
        /\(\d+-\d+ of 12\)/,
        "the hint counts the steps, not the fixed head",
      );

      // Paging up walks back through the steps the window hides.
      for (let page = 0; page < 5; page += 1) overlay.handleInput("\x1b[5~");
      const earlier = overlay.render(100).map(plainOf).join("\n");
      assert.match(earlier, /probe-0\b/, "paging up reveals older steps");
      assert.doesNotMatch(earlier, /probe-11/);
      assert.match(
        earlier,
        /\d\d:\d\d:\d\d start/,
        "the spawn line stays visible while paging back",
      );
      assert.match(earlier, /Escape to go back/);

      for (let page = 0; page < 5; page += 1) overlay.handleInput("\x1b[6~");
      assert.match(
        overlay.render(100).map(plainOf).join("\n"),
        /probe-11/,
        "paging back down follows the newest step again",
      );

      // A view that follows the end keeps doing so when steps arrive later.
      children[0].write(
        toolRecord("tool_execution_start", "call-late", "probe-late", {
          path: "late.ts",
        }),
      );
      assert.match(
        overlay.render(100).map(plainOf).join("\n"),
        /probe-late/,
        "a followed view shows steps that arrive later",
      );

      // A narrower terminal measures its own hint instead of the last frame's,
      // so a resize does not waste rows on a hint that no longer fits.
      const at40 = overlay.render(40).length;
      overlay.render(100);
      assert.equal(
        overlay.render(40).length,
        at40,
        "a resize keeps the body rows a fresh render gives",
      );

      overlay.handleInput("\x1b");
      overlay.handleInput("\x1b");
      await showing;
      await pi.hooks.get("session_shutdown")({ reason: "quit" });
    });

    test("/subagents scrolls its list to keep the selection in a short terminal", async (t) => {
      const { call, pi, children } = setup(t);
      const rows = 20;
      // The fake UI cannot verify the real reserve, but a page that grows past
      // it would clip.
      const screen = fakeUI(t, {}, rows);
      const showing = pi.commands
        .get("subagents")
        .handler("", { mode: "tui", ui: screen.ui });
      const overlay = screen.component;
      const ids = ["one", "two", "three", "four", "five", "six", "seven", "eight"];
      for (const id of ids) await call({ id, prompt: "x" });
      for (const child of children) child.close(0);
      await notices(pi, ids.length);

      /** The list as the user sees it, in a terminal this short. */
      const shown = () => {
        const lines = overlay.render(100);
        assert.ok(
          lines.length <= rows - VIEWPORT_RESERVE_ROWS,
          `page leaves pi its rows: ${lines.length} of ${rows}`,
        );
        return lines.map(plainOf).join("\n");
      };

      const first = shown();
      assert.match(first, /Subagents/);
      assert.match(first, /0 running, 8 finished/);
      assert.match(first, /Enter for details, Escape to close/);
      assert.doesNotMatch(first, /eight/);

      for (let move = 0; move < ids.length - 1; move += 1) {
        overlay.handleInput("\x1b[B");
      }
      const moved = shown();
      assert.match(
        moved,
        new RegExp(`${SELECTED_CURSOR} +eight`),
        "the selection stays visible while the list scrolls",
      );
      assert.doesNotMatch(moved, /\bone\b/);
      assert.match(moved, /Enter for details, Escape to close/);

      overlay.handleInput("\x1b");
      await showing;
      await pi.hooks.get("session_shutdown")({ reason: "quit" });
    });
  });

  describe("subagent_status", () => {
    test("subagent_status reports exited children only as finished while parent is busy", async (t) => {
      const { call, pi, children } = setup(t, { idle: () => false });
      await call({ id: "busy", prompt: "x", model: "m" });
      await call({ id: "done", prompt: "y" });
      children[1].write(assistantRecord("finished fine"));
      children[1].close(0);

      const status = pi.tools.get("subagent_status");
      const all = (await status.execute("call", {}, undefined, undefined, {})).content[0].text;
      assert.match(all, /\[subagent busy\] running for \d+s \(m, tools=default, /);
      assert.ok(all.includes(workDir), "the status shows the working directory");
      assert.match(all, /\[subagent done\] done after \d+s/);
      assert.doesNotMatch(all, /\[subagent done\] running/);
      assert.equal(pi.sent.length, 1);

      // Shutdown stops the remaining live child.
      await pi.hooks.get("session_shutdown")({ reason: "quit" });
    });

    test("subagent_status lists children that ended on their own", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "sent", prompt: "z" });
      children[0].write(assistantRecord("ok"));
      children[0].close(0);
      await notices(pi);
      const status = await pi.tools
        .get("subagent_status")
        .execute("call", {}, undefined, undefined, {});
      assert.match(status.content[0].text, /\[subagent sent\] done after \d+s/);
    });

    test("subagent_status records a failure with its reason", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "bad", prompt: "z" });
      children[0].close(3);
      await notices(pi);
      const status = await pi.tools
        .get("subagent_status")
        .execute("call", {}, undefined, undefined, {});
      assert.match(
        status.content[0].text,
        new RegExp(
          `\\[subagent bad\\] failed after \\d+s \\(timeout=${DEFAULT_TIMEOUT_SEC}s\\): exit code 3`,
        ),
      );
    });

    test("subagent_status narrows to the ids it is given", async (t) => {
      const { call, pi } = setup(t);
      await call({ id: "one", prompt: "x" });
      await call({ id: "two", prompt: "y" });
      const status = pi.tools.get("subagent_status");
      const run = (id) => status.execute("call", { id }, undefined, undefined, {}).then((r) => r.content[0].text);

      assert.match(await run("one"), /\[subagent one\]/);
      assert.doesNotMatch(await run("one"), /\[subagent two\]/);
      assert.match(await run(["one", "two"]), /\[subagent two\]/);
      assert.match(await run("one, two"), /\[subagent two\]/);
      assert.match(await run("ghost"), /No subagent named \[subagent ghost\]/);
    });

    test("subagent_status has no wait state before the run starts", async (t) => {
      const { call, pi, children } = setup(t);
      const advance = fakeClock(t);
      await call({ id: "quiet", prompt: "x" });
      const status = pi.tools.get("subagent_status");
      const report = () =>
        status
          .execute("call", {}, undefined, undefined, {})
          .then((result) => result.content[0].text);

      advance(2);
      const before = await report();
      assert.match(
        before,
        new RegExp(
          `^\\[subagent quiet\\] running for 2s \\(model=default, tools=default, .*timeout=${DEFAULT_TIMEOUT_SEC}s\\)$`,
          "m",
        ),
      );
      assert.doesNotMatch(before, /waiting/);

      // A response or UI record reports on a command, not on the child's work.
      children[0].write(
        `${JSON.stringify({ type: "response", command: "prompt", success: true, data: { disposition: "started" } })}\n`,
      );
      children[0].write(
        `${JSON.stringify({ type: "extension_ui_request", id: "ui-1", method: "confirm", title: "ok?" })}\n`,
      );
      children[0].write(
        `${JSON.stringify({ type: "queue_update", steering: [], followUp: [] })}\n`,
      );
      assert.equal(await report(), before, "unrelated records change nothing");

      // The run itself is what puts the child into the wait.
      children[0].write(eventRecord("agent_start"));
      advance(3);
      assert.ok(
        (await report()).includes(
          "[subagent quiet] running for 5s, waiting for the model (3s) (",
        ),
      );
    });

    test("subagent_status keeps one wait clock across lifecycle and token records", async (t) => {
      const { call, pi, children } = setup(t);
      const advance = fakeClock(t);
      await call({ id: "steady", prompt: "x" });
      const status = pi.tools.get("subagent_status");
      const report = () =>
        status
          .execute("call", {}, undefined, undefined, {})
          .then((result) => result.content[0].text);

      children[0].write(eventRecord("agent_start"));
      advance(2);
      // Duplicate lifecycle records of one run must not restart the clock.
      children[0].write(eventRecord("turn_start"));
      children[0].write(messageStartRecord("assistant"));
      assert.ok((await report()).includes("waiting for the model (2s)"));

      advance(3);
      // Preparing a reply streams tool-call arguments, which are not a block.
      children[0].write(updateRecord({ type: "toolcall_start", contentIndex: 0, id: "call-1", toolName: "bash" }));
      children[0].write(updateRecord({ type: "toolcall_delta", contentIndex: 0, delta: "{\"command\":" }));
      assert.ok((await report()).includes("waiting for the model (5s)"));

      // A streamed block measures its own lifetime, not the last token.
      children[0].write(updateRecord({ type: "text_start", contentIndex: 0 }));
      advance(4);
      children[0].write(updateRecord({ type: "text_delta", contentIndex: 0, delta: "draft" }));
      const writing = await report();
      assert.ok(writing.includes("running for 9s, writing for 4s (5 chars) ("), writing);
      assert.doesNotMatch(writing, /last event/);

      // Once the block ends, the wait starts over from that moment.
      children[0].write(updateRecord({ type: "text_end", contentIndex: 0, content: "draft" }));
      advance(2);
      const waiting = await report();
      assert.ok(waiting.includes("waiting for the model (2s)"), waiting);
    });

    test("subagent_status shows a child that is writing text", async (t) => {
      const { call, pi, children } = setup(t);
      const advance = fakeClock(t);
      await call({ id: "writer", prompt: "x" });
      const status = pi.tools.get("subagent_status");
      const report = () =>
        status
          .execute("call", {}, undefined, undefined, {})
          .then((result) => result.content[0].text);
      const first = "Reading the tests now.\nAlmost done";

      children[0].write(updateRecord({ type: "text_start", contentIndex: 0 }));
      children[0].write(
        updateRecord({ type: "text_delta", contentIndex: 0, delta: first }),
      );
      advance(3);
      const writing = await report();
      assert.ok(
        writing.includes(
          `[subagent writer] running for 3s, writing for 3s (${first.length} chars) (`,
        ),
        writing,
      );
      assert.match(writing, /^ {2}"\.\.\.Almost done"$/m);

      advance(2);
      children[0].write(
        updateRecord({
          type: "text_delta",
          contentIndex: 0,
          delta: " with this",
        }),
      );
      const grown = await report();
      assert.ok(
        grown.includes(
          `writing for 5s (${first.length + " with this".length} chars)`,
        ),
        grown,
      );
      assert.match(grown, /"\.\.\.Almost done with this"/);
    });

    test("subagent_status shows a thinking child without its words", async (t) => {
      const { call, pi, children } = setup(t);
      const advance = fakeClock(t);
      await call({ id: "thinker", prompt: "x" });
      const status = pi.tools.get("subagent_status");
      const report = () =>
        status
          .execute("call", {}, undefined, undefined, {})
          .then((result) => result.content[0].text);
      const thoughts = "hidden chain of thought";

      children[0].write(
        updateRecord({ type: "thinking_start", contentIndex: 0 }),
      );
      advance(4);
      children[0].write(
        updateRecord({ type: "thinking_delta", contentIndex: 0, delta: thoughts }),
      );
      const text = await report();
      assert.ok(
        text.includes(
          `[subagent thinker] running for 4s, thinking for 4s (${thoughts.length} chars) (`,
        ),
        text,
      );
      assert.doesNotMatch(text, /hidden chain of thought/);
      assert.doesNotMatch(text, /"\.\.\./);

      children[0].write(
        updateRecord({
          type: "thinking_end",
          contentIndex: 0,
          content: thoughts,
        }),
      );
      advance(7);
      const waiting = await report();
      assert.ok(waiting.includes("waiting for the model (7s)"), waiting);
    });

    test("subagent_status stops reporting a block once its message ends", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "cut", prompt: "x" });
      const status = pi.tools.get("subagent_status");
      const report = () =>
        status
          .execute("call", {}, undefined, undefined, {})
          .then((result) => result.content[0].text);

      // An aborted stream ends the message without closing its blocks.
      children[0].write(
        updateRecord({ type: "thinking_delta", contentIndex: 0, delta: "a" }),
      );
      children[0].write(
        updateRecord({ type: "text_delta", contentIndex: 1, delta: "partial" }),
      );
      children[0].write(assistantRecord("partial", { stopReason: "aborted" }));

      const text = await report();
      assert.match(text, /, waiting for the model \(\d+s\) \(/);
      assert.doesNotMatch(text, /thinking|writing|"\.\.\./);
    });

    test("a user message does not end the assistant's work", async (t) => {
      const { call, pi, children } = setup(t);
      const advance = fakeClock(t);
      await call({ id: "mixed", prompt: "x" });
      const status = pi.tools.get("subagent_status");
      const report = () =>
        status
          .execute("call", {}, undefined, undefined, {})
          .then((result) => result.content[0].text);

      children[0].write(eventRecord("agent_start"));
      children[0].write(messageStartRecord("assistant"));
      children[0].write(
        updateRecord({ type: "text_delta", contentIndex: 0, delta: "half a sen" }),
      );
      advance(2);
      children[0].write(
        messageEndRecord("user", [{ type: "text", text: "hi" }]),
      );
      assert.ok((await report()).includes("writing for 2s (10 chars)"));

      // The assistant's own message_end closes the block and waits again.
      advance(3);
      children[0].write(messageEndRecord("assistant", [{ type: "text", text: "half a sentence" }]));
      const waiting = await report();
      assert.ok(waiting.includes("waiting for the model (0s)"), waiting);
      assert.doesNotMatch(waiting, /writing|"\.\.\./);

      advance(4);
      assert.ok((await report()).includes("waiting for the model (4s)"));
    });

    test("agent_end does not mean idle; agent_settled does", async (t) => {
      const { call, pi, children } = setup(t);
      const advance = fakeClock(t);
      await call({ id: "settler", prompt: "x" });
      const status = pi.tools.get("subagent_status");
      const report = () =>
        status
          .execute("call", {}, undefined, undefined, {})
          .then((result) => result.content[0].text);

      children[0].write(eventRecord("agent_start"));
      children[0].write(
        updateRecord({ type: "thinking_start", contentIndex: 0 }),
      );
      advance(4);
      assert.ok((await report()).includes("thinking for 4s (0 chars)"));

      // A low-level run ending can be followed by a retry, so it is not idle.
      children[0].write(eventRecord("agent_end"));
      advance(3);
      const ended = await report();
      assert.ok(ended.includes("thinking for 7s (0 chars)"), ended);
      assert.doesNotMatch(ended, /idle/);

      // Settled overrides the step that never closed.
      children[0].write(eventRecord("agent_settled"));
      advance(9);
      const settled = await report();
      assert.ok(
        settled.includes("idle, waiting on background work (9s)"),
        settled,
      );
      assert.doesNotMatch(settled, /thinking|waiting for the model/);

      // A late tool end cannot undo settled idle.
      children[0].write(toolRecord("tool_execution_end", "call-late", "bash"));
      assert.ok(
        (await report()).includes("idle, waiting on background work (9s)"),
      );

      // A genuine new run waits for the model again, from zero.
      children[0].write(eventRecord("agent_start"));
      const restarted = await report();
      assert.ok(restarted.includes("waiting for the model (0s)"), restarted);
      assert.doesNotMatch(restarted, /idle/);
    });

    test("subagent_status reports an open tool while another finishes", async (t) => {
      const { call, pi, children } = setup(t);
      const advance = fakeClock(t);
      await call({ id: "pair", prompt: "x" });
      const status = pi.tools.get("subagent_status");
      const report = () =>
        status
          .execute("call", {}, undefined, undefined, {})
          .then((result) => result.content[0].text);

      children[0].write(
        toolRecord("tool_execution_start", "call-1", "bash", {
          command: "npm test",
        }),
      );
      children[0].write(
        toolRecord("tool_execution_start", "call-2", "read", {
          path: "src/app.ts",
        }),
      );
      advance(2);
      children[0].write(toolRecord("tool_execution_end", "call-1", "bash"));
      const one = await report();
      assert.ok(one.includes("read `src/app.ts` (2s)"), one);
      assert.doesNotMatch(one, /waiting for the model/);
      assert.doesNotMatch(one, /npm test/);

      children[0].write(toolRecord("tool_execution_end", "call-2", "read"));
      advance(3);
      assert.ok((await report()).includes("waiting for the model (3s)"));
    });

    test("subagent_status names the tool a child is running, then waits", async (t) => {
      const { call, pi, children } = setup(t);
      const advance = fakeClock(t);
      await call({ id: "worker", prompt: "x" });
      const status = pi.tools.get("subagent_status");
      const report = () =>
        status
          .execute("call", {}, undefined, undefined, {})
          .then((result) => result.content[0].text);

      children[0].write(
        toolRecord("tool_execution_start", "call-1", "bash", {
          command: "npm test",
        }),
      );
      advance(2);
      assert.ok(
        (await report()).includes(
          "[subagent worker] running for 2s, bash `npm test` (2s) (",
        ),
      );

      children[0].write(toolRecord("tool_execution_end", "call-1", "bash"));
      advance(3);
      const after = await report();
      assert.ok(after.includes("waiting for the model (3s)"), after);
      assert.doesNotMatch(after, /npm test/);
    });
  });

  describe("subagent_kill and shutdown", () => {
    test("subagent_kill stops one id, a list, or everything", async (t) => {
      const { call, pi, children } = setup(t);
      const kill = pi.tools.get("subagent_kill");
      const run = (id) => kill.execute("call", { id }, undefined, undefined, {}).then((r) => r.content[0].text);

      await call({ id: "keep", prompt: "x" });
      await call({ id: "drop", prompt: "y" });
      await call({ id: "drop2", prompt: "z" });

      assert.match(await run("drop"), /Stopped \[subagent drop\]\./);
      // A fake child never exits on its own, so the escalation ends up at SIGKILL.
      assert.deepEqual(children[1].kills, ["SIGTERM", "SIGKILL"]);
      assert.deepEqual(children[0].kills, [], "other children are untouched");

      assert.match(await run(["drop2", "ghost"]), /Stopped \[subagent drop2\]\. Not running: \[subagent ghost\]\./);
      assert.match(await run("nobody"), /No running subagent named \[subagent nobody\]\./);

      // No id: everything that is left.
      assert.match(await run(undefined), /Stopped \[subagent keep\]\./);
      assert.deepEqual(children[0].kills, ["SIGTERM", "SIGKILL"]);
    });

    test("a killed child does not report a result", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "killed", prompt: "x" });
      await pi.tools.get("subagent_kill").execute("call", {}, undefined, undefined, {});
      children[0].write(assistantRecord("late answer"));
      children[0].close(0);
      await new Promise((resolve) => setTimeout(resolve, 20));
      assert.equal(pi.sent.length, 0, "no finished notice after a kill");
      const status = await pi.tools
        .get("subagent_status")
        .execute("call", {}, undefined, undefined, {});
      assert.match(status.content[0].text, /\[subagent killed\] killed after \d+s/);
    });

    test("shutdown drops late child results", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "late", prompt: "x" });
      await pi.hooks.get("session_shutdown")({ reason: "quit" });
      children[0].write(assistantRecord("too late"));
      children[0].close(0);
      assert.equal(pi.sent.length, 0);
    });

    test("late close from a killed child preserves a reused id", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "reuse", prompt: "old" });
      const old = children[0];
      await pi.tools.get("subagent_kill").execute("call", { id: "reuse" });
      await call({ id: "reuse", prompt: "new" });
      old.close(0);
      const status = await pi.tools.get("subagent_status").execute("call", {});
      assert.match(status.content[0].text, /\[subagent reuse\] running/);
      await pi.tools.get("subagent_kill").execute("call", { id: "reuse" });
      assert.deepEqual(children[1].kills, ["SIGTERM", "SIGKILL"]);
      assert.equal(pi.sent.length, 0);
    });

    test("shutdown kills children and says a reload killed them", async (t) => {
      const { call, pi, children } = setup(t, { idle: () => false });
      await call({ id: "alive", prompt: "x" });
      assert.deepEqual(children[0].kills, [], "nothing is killed while the child runs");
      await pi.hooks.get("session_shutdown")({ reason: "reload" });
      assert.deepEqual(children[0].kills, ["SIGTERM", "SIGKILL"], "shutdown stops the child");
      const sent = await notices(pi);
      assert.match(sent[0].message.content, /Reload killed 1 running subagent\(s\): \[subagent alive\]/);
      assert.deepEqual(sent[0].options, { triggerTurn: false });
    });
  });

  describe("subagent_update", () => {
    /**
     * Call `subagent_update` on a fake pi.
     *
     * @param pi - Fake pi holding the registered tool.
     * @param params - Tool parameters.
     * @returns The text the agent reads back.
     */
    async function update(pi, params) {
      const result = await pi.tools
        .get("subagent_update")
        .execute("call", params, undefined, undefined, {});
      return result.content[0].text;
    }

    test("a longer timeout keeps a child alive past its old deadline", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "grown", prompt: "x", timeoutSec: 0.3 });
      // The new deadline lands well after the old one, so a slow machine cannot
      // blur which of the two fired.
      const text = await update(pi, { id: "grown", timeoutSec: 1 });
      assert.match(text, /\[subagent grown\] timeout changed from 0\.3s to 1s/);

      await new Promise((resolve) => setTimeout(resolve, 500));
      assert.equal(pi.sent.length, 0, "the old deadline no longer fires");
      assert.deepEqual(children[0].kills, []);

      const [sent] = await notices(pi);
      assert.match(
        sent.message.content,
        /^\[subagent grown\] timeout after \d+s: no result within its 1s timeout/,
      );
      const status = await pi.tools
        .get("subagent_status")
        .execute("call", { id: "grown" }, undefined, undefined, {});
      assert.match(status.content[0].text, /\(timeout=1s\)/);
    });

    test("the child is told its new limit", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "told", prompt: "x", timeoutSec: 60 });
      await update(pi, { id: "told", timeoutSec: 120 });
      const last = childCommands(children[0]).at(-1);
      assert.equal(last.type, "prompt");
      assert.equal(last.message, "/subagent-timeout 120");
    });

    test("a deadline the child has already passed is refused", async (t) => {
      const advance = fakeClock(t);
      const { call, pi, children } = setup(t);
      await call({ id: "late", prompt: "x", timeoutSec: 60 });
      advance(30);
      const text = await update(pi, { id: "late", timeoutSec: 20 });
      assert.match(text, /already run for 30\.0s/);
      assert.equal(childCommands(children[0]).length, 1, "the child hears nothing");
    });

    test("a shorter timeout ends the child sooner", async (t) => {
      const { call, pi } = setup(t);
      await call({ id: "shrunk", prompt: "x", timeoutSec: 60 });
      await update(pi, { id: "shrunk", timeoutSec: 0.1 });
      const [sent] = await notices(pi);
      assert.match(
        sent.message.content,
        /^\[subagent shrunk\] timeout after \d+s: no result within its 0\.1s timeout/,
      );
    });

    test("a killed child can no longer be updated", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "gone", prompt: "x" });
      await pi.tools.get("subagent_kill").execute("call", { id: "gone" });
      assert.match(
        await update(pi, { id: "gone", timeoutSec: 60 }),
        /No running subagent named \[subagent gone\]/,
      );
      assert.equal(childCommands(children[0]).length, 1, "the dead child hears nothing");
    });

    test("only a running child can be updated", async (t) => {
      const { call, pi, children } = setup(t);
      assert.match(
        await update(pi, { id: "ghost", timeoutSec: 60 }),
        /No running subagent named \[subagent ghost\]/,
      );
      await call({ id: "over", prompt: "x" });
      children[0].write(assistantRecord("done"));
      children[0].close(0);
      await notices(pi);
      assert.match(
        await update(pi, { id: "over", timeoutSec: 60 }),
        /No running subagent named \[subagent over\]/,
      );
      assert.match(
        await update(pi, { id: "over", timeoutSec: 0 }),
        /must be a positive number/,
      );
    });

    test("the update command is not mistaken for a refused task", async (t) => {
      const { call, pi, children } = setup(t);
      await call({ id: "steady", prompt: "x" });
      await update(pi, { id: "steady", timeoutSec: 7200 });
      children[0].write(
        rpcRecord({
          id: "timeout-update",
          type: "response",
          command: "prompt",
          success: true,
          data: { disposition: "handled" },
        }),
      );
      children[0].write(assistantRecord("all good"));
      children[0].close(0);
      const [sent] = await notices(pi);
      assert.match(sent.message.content, /^\[subagent steady\] finished in/);
    });
  });

  describe("the child keep-alive gate", () => {
    /**
     * Install the extension the way a spawned child loads it.
     *
     * @param t - Node test context, used to restore the environment variable.
     * @returns The fake pi holding the registered gate.
     */
    function childSetup(t, { timeout } = {}) {
      const previousChild = process.env.PI_SUBAGENT_CHILD;
      const previousTimeout = process.env.PI_SUBAGENT_TIMEOUT_SEC;
      process.env.PI_SUBAGENT_CHILD = "1";
      if (timeout !== undefined) process.env.PI_SUBAGENT_TIMEOUT_SEC = timeout;
      else delete process.env.PI_SUBAGENT_TIMEOUT_SEC;
      t.after(() => {
        if (previousChild === undefined) delete process.env.PI_SUBAGENT_CHILD;
        else process.env.PI_SUBAGENT_CHILD = previousChild;
        if (previousTimeout === undefined)
          delete process.env.PI_SUBAGENT_TIMEOUT_SEC;
        else process.env.PI_SUBAGENT_TIMEOUT_SEC = previousTimeout;
      });
      resetChildren();
      shortKillGrace(t);
      const pi = fakePi();
      installSubagent(pi.api);
      return pi;
    }

    /**
     * A settle context that records whether the child was asked to end.
     *
     * @param idle - What `isIdle()` reports.
     * @returns The context, and the state it records.
     */
    function settleCtx({ idle = true } = {}) {
      const state = { shutDown: 0 };
      return {
        state,
        ctx: {
          isIdle: () => idle,
          hasPendingMessages: () => false,
          shutdown: () => {
            state.shutDown += 1;
          },
        },
      };
    }

    test("a parent session installs no gate", async (t) => {
      const { pi } = setup(t);
      assert.equal(pi.hooks.has("agent_settled"), false);
      assert.equal(pi.tools.has("subagent_finish"), false, "a parent has nothing to finish");
      assert.equal(
        pi.commands.has("subagent-timeout"),
        false,
        "a parent does not take deadline updates meant for a child",
      );
    });

    test("a child sees the finish tool even when its selection hides it", async (t) => {
      const pi = childSetup(t);
      await pi.tools
        .get("subagent")
        .execute("call", { id: "sel", prompt: "x", tools: ["read"] }, undefined, undefined, {
          cwd: workDir,
        });
      const toolSelection = childOptions(children[0]).options.tools;
      assert.deepEqual(toolSelection.split(","), ["read", "subagent_finish"]);
    });

    test("the finish declaration carries only the finish contract", async (t) => {
      const pi = childSetup(t);
      const finish = pi.tools.get("subagent_finish");
      const guidelines = finish.promptGuidelines.join(" ");
      assert.match(finish.promptSnippet, /a turn ending does not end the session/);
      assert.doesNotMatch(guidelines, /You are a subagent working alone/);
      assert.doesNotMatch(guidelines, /outlives its turns/);
      assert.match(guidelines, /call `subagent_finish` when your answer is final/);
    });

    test("a child stays open after a turn until its model finishes", async (t) => {
      const pi = childSetup(t);
      const { ctx, state } = settleCtx();
      await pi.hooks.get("agent_settled")({ aborted: false }, ctx);
      assert.equal(state.shutDown, 0, "a turn ending no longer ends the session");
    });

    test("the finish tool ends the child at the next settle", async (t) => {
      const pi = childSetup(t);
      const { ctx, state } = settleCtx();
      const result = await pi.tools
        .get("subagent_finish")
        .execute("call", { answer: "x" });
      assert.match(result.content[0].text, /Finishing/);
      assert.equal(result.terminate, true, "the answer already carries the report");
      await pi.hooks.get("agent_settled")({ aborted: false }, ctx);
      assert.equal(state.shutDown, 1);
    });

    test("a child is warned once shortly before its deadline", async (t) => {
      // A sub-second timeout keeps the test fast: half of it is the lead.
      const pi = childSetup(t, { timeout: "0.2" });
      const [sent] = await notices(pi);
      assert.equal(sent.message.customType, "subagent-deadline");
      assert.match(sent.message.content, /\[subagent deadline\] About 1s/);
      assert.match(sent.message.content, /call `subagent_finish` with your best answer/);
      assert.deepEqual(
        sent.options,
        { deliverAs: "steer", triggerTurn: true },
        "the warning is steered, and wakes an idle child",
      );
      assert.equal(pi.sent.length, 1, "the warning is sent once");
    });

    test("a child with no timeout is not warned", async (t) => {
      const pi = childSetup(t);
      await new Promise((resolve) => setTimeout(resolve, 150));
      assert.equal(pi.sent.length, 0);
    });

    test("a child that already asked to finish is not warned", async (t) => {
      const pi = childSetup(t, { timeout: "0.2" });
      await pi.tools.get("subagent_finish").execute("call", { answer: "x" });
      await new Promise((resolve) => setTimeout(resolve, 250));
      assert.equal(pi.sent.length, 0, "no warning after a finish request");
    });

    test("a moved deadline moves the warning and tells the model", async (t) => {
      const pi = childSetup(t, { timeout: "0.2" });
      // The new warning lands at 1s, far from the old one at 0.1s, so a slow
      // machine cannot blur which of the two fired.
      await pi.commands.get("subagent-timeout").handler("2");
      const [told] = pi.sent;
      assert.match(told.message.content, /limit to 2s/);
      assert.deepEqual(
        told.options,
        { triggerTurn: false },
        "the model learns it at its next request, without being woken",
      );

      await new Promise((resolve) => setTimeout(resolve, 200));
      assert.equal(pi.sent.length, 1, "the old warning no longer fires");
      await waitFor(() => pi.sent.length === 2);
      assert.match(pi.sent[1].message.content, /of this session's 2s budget/);
    });

    test("a deadline moved into the warning window warns at once with the time left", async (t) => {
      // A 100s limit warns 10s ahead; moving it to 1s from the start lands
      // inside that lead, so the warning must say what is really left.
      const pi = childSetup(t, { timeout: "100" });
      await pi.commands.get("subagent-timeout").handler("1");
      await waitFor(() => pi.sent.length === 2);
      assert.match(pi.sent[1].message.content, /About 1s of this session's 1s budget/);
    });

    test("a finish request waits for a turn that is already running", async (t) => {
      const pi = childSetup(t);
      await pi.tools.get("subagent_finish").execute("call", { answer: "x" });
      const busy = settleCtx({ idle: false });
      await pi.hooks.get("agent_settled")({ aborted: false }, busy.ctx);
      assert.equal(busy.state.shutDown, 0, "a running turn reports first");

      const idle = settleCtx();
      await pi.hooks.get("agent_settled")({ aborted: false }, idle.ctx);
      assert.equal(idle.state.shutDown, 1);
    });
  });

  describe("delivery through a real session", () => {
    // The same finished-child notice, seen from the parent agent's queue instead
    // of the extension's `sendMessage`.

    /**
     * Create an idle SDK session with the real extension loaded.
     *
     * @param t - Node test context, used for cleanup.
     * @param customTools - Extra tools the scripted parent may call.
     * @param tools - Active tool names.
     * @returns The created session.
     */
    async function createSession(t, customTools = [], tools = ["subagent"]) {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-subagent-"));
      const resourceLoader = new DefaultResourceLoader({
        cwd: dir,
        agentDir: dir,
        noExtensions: true,
        noSkills: true,
        noPromptTemplates: true,
        noThemes: true,
        noContextFiles: true,
        systemPrompt: "You are a test assistant.",
        extensionFactories: [installSubagent],
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
      resetChildren();
      shortKillGrace(t);

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
      resetChildren();
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
  });
});
