import assert from "node:assert/strict";
import test from "node:test";

import watchExtension from "../extensions/watch.ts";

/** A command result, in the shape `pi.exec()` returns. */
const exit = (code, stdout = "") => ({ code, stdout, stderr: "" });

/**
 * Load the extension with a fake `pi`.
 *
 * @param runCommand - Fake shell: gets the command text and abort signal, and
 *   returns a command result. Commands run instantly, so tests never sleep.
 */
function setup(runCommand) {
  let tool;
  const hooks = new Map();
  const notices = [];
  let onNotice = () => {};
  watchExtension({
    registerTool: (definition) => {
      tool = definition;
    },
    on: (name, handler) => hooks.set(name, handler),
    exec: async (_bash, [_flag, command], { signal }) =>
      runCommand(command, signal),
    sendMessage: (message) => {
      notices.push(message);
      onNotice();
    },
  });
  const call = (params) => tool.execute("test", params);
  /** Wait until the watch sends `count` notifications in total. */
  const noticesAfter = (count) =>
    new Promise((resolve) => {
      onNotice = () => notices.length >= count && resolve(notices);
      onNotice();
    });
  /** Make a session branch that contains these tool results. */
  const branch = (...details) => ({
    sessionManager: {
      getBranch: () =>
        details.map((detail) => ({
          type: "message",
          message: { role: "toolResult", toolName: "watch", details: detail },
        })),
    },
  });
  return { hooks, call, noticesAfter, branch };
}

/** A fake shell whose commands keep running until the watch cancels them. */
function runUntilCancelled(_command, signal) {
  return new Promise((resolve) =>
    signal.addEventListener("abort", () => resolve(exit(null))),
  );
}

test("a watch reports done once its condition succeeds", async () => {
  const { call, noticesAfter } = setup((command) =>
    command === "tail log" ? exit(0, "build finished") : exit(0),
  );

  const start = await call({
    action: "start",
    command: "test -f done",
    tailCommand: "tail log",
  });
  const [notice] = await noticesAfter(1);

  assert.equal(start.details.id, "job-1");
  assert.equal(notice.details.state, "done");
  assert.match(notice.content, /\[watch job-1\] done\n\nbuild finished/);
});

test("a watch reports a timeout when its condition never succeeds", async () => {
  const { hooks, noticesAfter, branch } = setup(() => exit(1));
  // A watch whose time ran out while the session was closed.
  const expired = {
    action: "start",
    id: "job-1",
    command: "false",
    timeoutSec: 10,
    intervalSec: 60,
    startedAt: Date.now() - 11_000,
  };

  await hooks.get("session_start")({}, branch(expired));
  const [notice] = await noticesAfter(1);

  assert.equal(notice.details.state, "timeout");
});

test("stopping an unknown watch says it does not exist", async () => {
  const { call } = setup(runUntilCancelled);

  const stop = await call({ action: "stop", id: "job-9" });

  assert.equal(stop.content[0].text, "No active watch: job-9");
});

test("start without a command and stop without an id are rejected", async () => {
  const { call } = setup(runUntilCancelled);

  await assert.rejects(call({ action: "start" }), /requires command/);
  await assert.rejects(call({ action: "stop" }), /requires id/);
});

test("resuming a session restores its active watches", async () => {
  const { hooks, call, noticesAfter, branch } = setup(() => exit(0));
  const started = { action: "start", id: "job-3", command: "true" };
  const job = { ...started, timeoutSec: 60, intervalSec: 60 };

  await hooks.get("session_start")(
    {},
    branch({ ...job, startedAt: Date.now() }),
  );
  const [notice] = await noticesAfter(1);
  const next = await call({ action: "start", command: "true" });

  assert.equal(notice.details.id, "job-3");
  assert.equal(next.details.id, "job-4");
});

test("watches already stopped on the branch are not restarted", async () => {
  const { hooks, call, branch } = setup(runUntilCancelled);
  const job = {
    action: "start",
    id: "job-1",
    command: "sleep 1d",
    timeoutSec: 60,
    intervalSec: 60,
    startedAt: Date.now(),
  };

  await hooks.get("session_start")(
    {},
    branch(job, { action: "stop", id: "job-1" }),
  );

  const stop = await call({ action: "stop", id: "job-1" });
  assert.equal(stop.content[0].text, "No active watch: job-1");
});

test("a watch can still be stopped after the branch is restored again", async () => {
  const { hooks, call, branch } = setup(runUntilCancelled);
  const { details } = await call({ action: "start", command: "sleep 1d" });

  await hooks.get("session_tree")({}, branch(details));
  await new Promise(setImmediate);

  const stop = await call({ action: "stop", id: details.id });
  assert.equal(stop.content[0].text, `Stopped ${details.id}.`);
});
