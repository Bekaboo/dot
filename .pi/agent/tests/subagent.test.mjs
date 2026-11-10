/**
 * Tests for the subagent extension.
 *
 * The extension spawns a real pi process, so the interesting behaviour is the
 * seam around it: how a call becomes a child invocation, how the child's JSONL
 * output is read, how a finished child is reported, and that a child which
 * ends without an answer cannot pass as a success. The registered tool is
 * driven with a fake `pi`, and the module's `spawn` is swapped for a fake, so
 * every child outcome is reproducible without a model or a network.
 */

import assert from "node:assert/strict";
import test from "node:test";

import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const extensionPath = require.resolve("../extensions/subagent.ts");
const loadExtension = () => require(extensionPath).default ?? require(extensionPath);

/** Timeout for a notification that never arrives. */
const NOTICE_TIMEOUT_MS = 2_000;

/**
 * A fake `spawn` installed for the whole file, and the children it created.
 *
 * One stub for every test keeps the extension's module cache intact, which
 * matters because each test needs a fresh instance: `loadExtension` re-runs the
 * factory against a fresh fake `pi` instead of re-importing the module.
 */
const children = [];

/**
 * Create a fake child for the installed `spawn` stub.
 *
 * @param command - Command the extension asked to spawn.
 * @param args - Arguments for that command.
 * @param options - Spawn options.
 * @returns A controllable child process.
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
    /** Push text through the stderr handler. */
    writeErr(text) {
      listeners.get("stderr:data")?.(text);
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


// Built-in modules are shared singletons, so replacing `spawn` here is what the
// extension sees when it spawns its child.
process.getBuiltinModule("node:child_process").spawn = fakeChild;

/**
 * Replace `fs.statSync` so a fake working directory passes the cwd check.
 *
 * @param t - Node test context, used to restore the original.
 * @param onlyFor - Fake path that should report as a directory.
 */
function fakeDirectory(t) {
  const fs = require("node:fs");
  const previous = fs.statSync;
  fs.statSync = (path, options) =>
    path === "/work" ? { isDirectory: () => true } : previous(path, options);
  t.after(() => {
    fs.statSync = previous;
  });
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

/** A JSONL record carrying a completed assistant message. */
function assistantRecord(text, extra = {}) {
  return `${JSON.stringify({
    type: "message_end",
    message: { role: "assistant", content: [{ type: "text", text }], ...extra },
  })}\n`;
}

/**
 * Install a fresh extension instance.
 *
 * @param t - Node test context.
 * @returns The fake pi, the registered tool, and a `call` helper.
 */
function setup(t, { idle = () => true } = {}) {
  fakeDirectory(t);
  children.length = 0;
  // Keep the SIGTERM-to-SIGKILL escalation short, and restore it afterwards so
  // no other test file inherits the shortened grace.
  const grace = process.env.SUBAGENT_KILL_GRACE_MS;
  process.env.SUBAGENT_KILL_GRACE_MS = "20";
  t.after(() => {
    if (grace === undefined) delete process.env.SUBAGENT_KILL_GRACE_MS;
    else process.env.SUBAGENT_KILL_GRACE_MS = grace;
  });
  const pi = fakePi();
  loadExtension()(pi.api);
  const tool = pi.tools.get("subagent");
  const ctx = { cwd: "/work", isIdle: idle };
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
  const deadline = Date.now() + NOTICE_TIMEOUT_MS;
  while (pi.sent.length < count && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  return pi.sent;
}

test("builds the child invocation from the call", async (t) => {
  const { call, children } = setup(t);
  await call({ id: "cfg", prompt: "do it", model: "some/model", tools: ["read", "bash"] });
  const [child] = children;
  assert.equal(child.options.cwd, "/work");
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
  assert.deepEqual(sent.options, { triggerTurn: true });
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

test("waits for the parent to be idle before sending", async (t) => {
  let idle = false;
  const { call, pi, children } = setup(t, { idle: () => idle });
  await call({ id: "busy", prompt: "x" });
  children[0].write(assistantRecord("late"));
  children[0].close(0);
  await new Promise((resolve) => setTimeout(resolve, 50));
  assert.equal(pi.sent.length, 0, "nothing is sent while the parent is busy");
  idle = true;
  const [sent] = await notices(pi);
  assert.match(sent.message.content, /late/);
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
  assert.match(notified[0], /\[subagent listed\] running for 0s \(m, tools=read, \/work\)/);
});

test("subagent_status tells a slow child from a slow parent", async (t) => {
  const { call, pi, children } = setup(t, { idle: () => false });
  await call({ id: "busy", prompt: "x", model: "m" });
  await call({ id: "done", prompt: "y" });
  children[1].write(assistantRecord("finished fine"));
  children[1].close(0);

  const status = pi.tools.get("subagent_status");
  const all = (await status.execute("call", {}, undefined, undefined, {})).content[0].text;
  // One child is still working, the other is done and only waiting for idle.
  assert.match(all, /\[subagent busy\] running for \d+s \(m, tools=default, \/work\)/);
  assert.match(all, /\[subagent done\] running for \d+s \(result waiting for you to be idle\)/);

  // Shutdown ends both children, so this test leaves no pending idle poll.
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
  assert.match(status.content[0].text, /\[subagent bad\] failed after \d+s: exit code 3/);
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
  assert.match(status.content[0].text, /\[subagent killed\] killed after \d+s/);
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
