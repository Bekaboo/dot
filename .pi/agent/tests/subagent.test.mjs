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
import test from "node:test";

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
  const listeners = new Map();
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
      child.kills.push(signal);
      // A real process dies from the signal; close so stopProcess resolves.
      if (signal === "SIGKILL") child.close(null, signal);
    },
    /** Push text through the stdout handler, as a chunk of output. */
    write(text) {
      listeners.get("stdout:data")?.(text);
    },
    /** Finish the child with an exit code. */
    close(code = 0, signal = null) {
      child.exitCode = code;
      child.signalCode = signal;
      listeners.get("close")?.(code, signal);
    },
    /** Fail the spawn itself, as a missing executable would. */
    fail(message) {
      listeners.get("error")?.(new Error(message));
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

/** A fake `pi` that records what the extension registers and sends. */
function fakePi() {
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
    },
  };
}

/**
 * The child's arguments without the pi script that launched this process.
 *
 * @param child - Fake child created by `spawn`.
 * @returns The arguments pi itself would receive.
 */
const piArgs = (child) => child.args.slice(child.args.indexOf("-p"));

/**
 * Install a fresh extension instance against a fake `pi`.
 *
 * @param t - Node test context.
 * @param idle - Idle check reported by the fake context.
 * @param model - Model the fake context reports as the session's selection.
 * @param thinkingLevel - Thinking level the fake context reports.
 * @returns The fake pi, the registered tool, and a `call` helper.
 */
function setup(t, { idle = () => true, model, thinkingLevel } = {}) {
  children.length = 0;
  // Keep the SIGTERM-to-SIGKILL escalation short, and restore it afterwards so
  // no other test inherits the shortened grace.
  const grace = process.env.SUBAGENT_KILL_GRACE_MS;
  process.env.SUBAGENT_KILL_GRACE_MS = "20";
  t.after(() => {
    if (grace === undefined) delete process.env.SUBAGENT_KILL_GRACE_MS;
    else process.env.SUBAGENT_KILL_GRACE_MS = grace;
  });
  const pi = fakePi();
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

/**
 * A fake extension UI that opens a custom component like the TUI mode does.
 *
 * @param t - Node test context, used to dispose a component left open.
 * @returns The fake UI, its notifications, and the open component.
 */
function fakeUI(t) {
  const notified = [];
  let component;
  const tui = { requestRender() {} };
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
          component = factory(tui, theme, undefined, done);
        });
      },
    },
  };
}

/**
 * Visible width of a rendered line without its ANSI attributes.
 *
 * @param line - Rendered widget line.
 * @returns Number of terminal columns it occupies.
 */
function widthOf(line) {
  return line.replace(/\x1b\[[0-9;]*m/g, "").length;
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

test("builds the child invocation from the call", async (t) => {
  const { call, children } = setup(t);
  await call({ id: "cfg", prompt: "do it", model: "some/model", tools: ["read", "bash"] });
  const [child] = children;
  assert.equal(child.options.cwd, workDir);
  assert.equal(child.options.shell, false);
  assert.deepEqual(piArgs(child).slice(0, 6), [
    "-p",
    "--mode",
    "json",
    "--no-session",
    "--model",
    "some/model",
  ]);
  assert.equal(piArgs(child)[6], "--tools");
  assert.equal(piArgs(child)[7], "read,bash");
  assert.ok(piArgs(child).includes("Task: do it"), "the prompt is a positional argument");
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
  const [child] = children;
  assert.ok(!piArgs(child).includes("--model"));
  assert.ok(!piArgs(child).includes("--tools"));
});

test("inherits the session's model and thinking level", async (t) => {
  const { call, children } = setup(t, {
    model: { provider: "qoder", id: "Fast" },
    thinkingLevel: "high",
  });
  const result = await call({ id: "inherit", prompt: "x" });
  const [child] = children;
  assert.deepEqual(piArgs(child).slice(4, 8), [
    "--model",
    "qoder/Fast",
    "--thinking",
    "high",
  ]);
  assert.match(result.content[0].text, /model=qoder\/Fast/);
});

test("an explicit model wins over the session's selection", async (t) => {
  const { call, children } = setup(t, {
    model: { provider: "qoder", id: "Fast" },
    thinkingLevel: "high",
  });
  await call({ id: "explicit", prompt: "x", model: "some/model:low" });
  const [child] = children;
  assert.equal(piArgs(child)[5], "some/model:low");
  assert.ok(
    !piArgs(child).includes("--thinking"),
    "a `:level` suffix already carries the level",
  );
});

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

test("rejects an empty id, a live duplicate, and a non-directory cwd", async (t) => {
  const { call } = setup(t);
  assert.match((await call({ id: "", prompt: "x" })).content[0].text, /must not be empty/);
  assert.match((await call({ id: "dup", prompt: "x" })).content[0].text, /started/);
  assert.match((await call({ id: "dup", prompt: "x" })).content[0].text, /already running/);
  const bad = await call({ id: "bad", prompt: "x", cwd: "/etc/hosts" });
  assert.match(bad.content[0].text, /not a directory/);
});

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
  // One record past the 8 MiB cap, then a complete answer in the same chunk.
  children[0].write(`${"x".repeat(9 * 1024 * 1024)}\n${assistantRecord("after the big one")}`);
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

test("a spawn failure is reported once", async (t) => {
  const { call, pi, children } = setup(t);
  await call({ id: "enoent", prompt: "x" });
  children[0].fail("spawn pi ENOENT");
  children[0].close(-2);
  const sent = await notices(pi);
  assert.equal(sent.length, 1, "error and close do not both report");
  assert.match(sent[0].message.content, /spawn error: spawn pi ENOENT/);
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
  assert.equal(notified[0], `[subagent listed] running for 0s (m, tools=read, ${workDir})`);
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
  children[0].write(
    `${JSON.stringify({
      type: "message_update",
      assistantMessageEvent: {
        type: "text_delta",
        contentIndex: 0,
        delta: "working on it",
      },
    })}\n`,
  );
  // Rendered wide, so the row's real working directory leaves room for the
  // last message; width handling is checked below.
  assert.match(overlay.render(160).join("\n"), /working on it/);
  // The first child finishes while the second keeps running; creation order
  // still decides the row order.
  children[0].write(assistantRecord("first done"));
  children[0].close(0);

  const lines = overlay.render(160);
  const text = lines.join("\n");
  assert.match(text, /1 running, 1 finished/);
  assert.ok(text.indexOf("first") < text.indexOf("second"));
  assert.match(text, /first done/);
  assert.match(text, /[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] second +work +0s/);

  // Every row starts its tools and cwd columns at the same offset.
  const firstRow = lines.find((line) => line.includes(" first "));
  const secondRow = lines.find((line) => line.includes(" second "));
  assert.ok(firstRow && secondRow, "both subagents are listed");
  assert.match(firstRow, / first +done /);
  assert.equal(
    firstRow.indexOf("done "),
    secondRow.indexOf("work "),
    "status column is aligned",
  );
  assert.equal(
    firstRow.indexOf("0s"),
    secondRow.indexOf("0s"),
    "elapsed column is aligned",
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

  // The last message is cut to the terminal width with an ellipsis.
  children[1].write(
    `${JSON.stringify({
      type: "message_update",
      assistantMessageEvent: {
        type: "text_delta",
        contentIndex: 0,
        delta: "x".repeat(200),
      },
    })}\n`,
  );
  const narrow = overlay.render(40);
  assert.ok(narrow.some((line) => line.includes("...")));
  for (const line of narrow) assert.equal(widthOf(line), 40);

  overlay.handleInput("\x1b");
  await showing;
  assert.equal(screen.component, undefined, "Escape closes the overlay");

  await pi.hooks.get("session_shutdown")({ reason: "quit" });
});

test("/subagents overlay shows the tail of the last message", async (t) => {
  const { call, pi, children } = setup(t);
  const screen = fakeUI(t);
  const showing = pi.commands.get("subagents").handler("", {
    mode: "tui",
    ui: screen.ui,
  });
  const overlay = screen.component;
  await call({ id: "tail", prompt: "x" });

  children[0].write(assistantRecord("earlier line\n\nlatest line"));
  const text = overlay.render(160).join("\n");
  assert.match(text, /latest line/);
  assert.doesNotMatch(text, /earlier line/);

  children[0].write(
    `${JSON.stringify({
      type: "message_update",
      assistantMessageEvent: {
        type: "text_delta",
        contentIndex: 0,
        delta: `${"x".repeat(200)}LATEST`,
      },
    })}\n`,
  );
  const row = overlay.render(160).find((line) => line.includes(" tail "));
  assert.ok(row, "the subagent is still listed");
  assert.match(row, /\.\.\.x+LATEST/);

  overlay.handleInput("\x1b");
  await showing;
  await pi.hooks.get("session_shutdown")({ reason: "quit" });
});

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
  assert.match(status.content[0].text, /\[subagent bad\] fail after \d+s: exit code 3/);
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
  assert.match(status.content[0].text, /\[subagent killed\] kill after \d+s/);
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

test("shutdown kills children and says a reload cancelled them", async (t) => {
  const { call, pi, children } = setup(t, { idle: () => false });
  await call({ id: "alive", prompt: "x" });
  assert.deepEqual(children[0].kills, [], "nothing is killed while the child runs");
  await pi.hooks.get("session_shutdown")({ reason: "reload" });
  assert.deepEqual(children[0].kills, ["SIGTERM", "SIGKILL"], "shutdown stops the child");
  const sent = await notices(pi);
  assert.match(sent[0].message.content, /Reload cancelled 1 running subagent\(s\): \[subagent alive\]/);
  assert.deepEqual(sent[0].options, { triggerTurn: false });
});

// Delivery through a real SDK session: the same finished-child notice, seen
// from the parent agent's queue instead of the extension's `sendMessage`.

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
