import assert from "node:assert/strict";
import test from "node:test";

import watchExtension from "../extensions/watch.ts";

/** A command result, in the shape `pi.exec()` returns. */
const exit = (code, stdout = "") => ({ code, stdout, stderr: "" });

/**
 * Load the extension with a fake `pi`.
 *
 * @param runCommand - Fake shell: gets the command text and abort signal, and
 *   returns a command result. Commands run instantly, so only tick intervals
 *   make a test wait.
 */
function setup(t, runCommand, { ack = true } = {}) {
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
    sendMessage: (message, options) => {
      notices.push({ ...message, options });
      onNotice();
      // A wake starts a turn in which the agent acts, which clears the pending
      // flag. Tests that exercise coalescing pass `ack: false`.
      if (ack) {
        queueMicrotask(() => hooks.get("tool_call")({}));
      }
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
  t.after(() => hooks.get("session_shutdown")({}));
  return { hooks, call, notices, noticesAfter, branch };
}

/** A fake shell whose commands keep running until the watch cancels them. */
function runUntilCancelled(_command, signal) {
  return new Promise((resolve) =>
    signal.addEventListener("abort", () => resolve(exit(null))),
  );
}

/** Resolve after `ms` milliseconds, so a poll loop can reach its next tick. */
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

test("a watch wakes with 'condition met' as soon as its condition holds", async (t) => {
  const { call, noticesAfter } = setup(t, () => exit(0));

  const start = await call({
    action: "start",
    id: "build-done",
    condition: "test -f done",
    maxTicks: 0,
  });
  const [notice] = await noticesAfter(1);

  assert.equal(start.details.id, "build-done");
  assert.equal(notice.content, '[watch build-done] condition met after 0s: test -f done');
  assert.equal(notice.details.state, "done");
  assert.equal(notice.options.deliverAs, "steer");
});

test("a watch reports a timeout when its deadline passes", async (t) => {
  const { hooks, noticesAfter, branch } = setup(t, () => exit(1));
  // A watch whose time ran out while the session was closed.
  const expired = {
    action: "start",
    id: "stale-watch",
    condition: "false",
    intervalSec: 1,
    maxTicks: 0,
    timeoutSec: 1,
    startedAt: Date.now() - 2_000,
  };

  await hooks.get("session_start")({}, branch(expired));
  const [notice] = await noticesAfter(1);

  assert.equal(notice.content, "[watch stale-watch] timeout after 1s");
  assert.equal(notice.details.state, "timeout");
});

test("stopping an unknown watch lists the active ones", async (t) => {
  const { call } = setup(t, runUntilCancelled);
  await call({ action: "start", id: "watch-a", condition: "false" });
  await call({ action: "start", id: "watch-b", condition: "false" });

  await assert.rejects(
    call({ action: "stop", id: "watch-c" }),
    /No watch "watch-c"; active: watch-a, watch-b\./,
  );
  const stop = await call({ action: "stop", id: "watch-a" });
  assert.equal(stop.content[0].text, 'Stopped "watch-a".');
});

test("start rejects a missing id, a nameless timer, and a bad id", async (t) => {
  const { call } = setup(t, runUntilCancelled);

  await assert.rejects(call({ action: "start" }), /requires id/);
  await assert.rejects(
    call({ action: "start", id: "peek-1", intervalSec: 1, maxTicks: 0 }),
    /could never wake you/,
  );
  await assert.rejects(
    call({ action: "start", id: "bad id!", condition: "false" }),
    /Invalid watch id/,
  );
});

test("start rejects a duplicate id and an unreachable tick", async (t) => {
  const { call } = setup(t, runUntilCancelled);
  await call({ action: "start", id: "watch-a", condition: "false" });

  await assert.rejects(
    call({ action: "start", id: "watch-a", condition: "false" }),
    /already active/,
  );
  await assert.rejects(
    call({
      action: "start",
      id: "watch-b",
      intervalSec: 30,
      timeoutSec: 10,
      maxTicks: 1,
    }),
    /cannot tick/,
  );
});

test("a one-shot timer wakes once, then retires itself", async (t) => {
  const { call, noticesAfter } = setup(t, () => exit(1));

  await call({
    action: "start",
    id: "peek-1",
    intervalSec: 1,
    maxTicks: 1,
    timeoutSec: 5,
  });
  const [notice] = await noticesAfter(1);

  assert.match(notice.content, /^\[watch peek-1\] tick 1\/1, \ds elapsed$/);
  await wait(50);
  await assert.rejects(
    call({ action: "status", id: "peek-1" }),
    /No watch "peek-1"; nothing is active\./,
  );
});

test("a timer ticks exactly maxTicks times", async (t) => {
  const { call, notices } = setup(t, () => exit(1));

  await call({
    action: "start",
    id: "monitor-1",
    intervalSec: 1,
    maxTicks: 2,
    timeoutSec: 10,
  });
  await wait(2_400);

  assert.equal(notices.length, 2);
  assert.match(notices[0].content, /^\[watch monitor-1\] tick 1\/2, \d+s elapsed$/);
  assert.match(notices[1].content, /^\[watch monitor-1\] tick 2\/2, \d+s elapsed$/);
});

test("a tick is dropped while the previous one is still unread", async (t) => {
  const { call, notices, hooks } = setup(t, () => exit(1), { ack: false });

  await call({
    action: "start",
    id: "busy-watch",
    intervalSec: 1,
    maxTicks: 2,
    timeoutSec: 10,
  });
  await wait(1_300);
  assert.equal(notices.length, 1);

  // The agent acts on the wake, so the next tick may be delivered again.
  await hooks.get("tool_call")({});
  await wait(1_200);

  assert.equal(notices.length, 2);
  assert.match(notices[1].content, /tick 2\/2/);
});

test("maxTicks 0 silences a condition watch until it finishes", async (t) => {
  const { call, notices } = setup(t, () => exit(1));

  const start = await call({
    action: "start",
    id: "quiet-watch",
    condition: "false",
    intervalSec: 1,
    maxTicks: 0,
    timeoutSec: 5,
  });
  await wait(1_200);

  // A tick would mean the budget was ignored; a terminal notice may still race
  // in on a loaded machine, so assert on the kind of notice, not the count.
  assert.deepEqual(
    notices.filter((notice) => notice.details.state === "tick"),
    [],
  );
  assert.equal(
    start.content[0].text,
    'Armed "quiet-watch": no ticks; ends when the condition first exits 0 or after 5s. Wakes arrive even after you end your turn.',
  );
});

test("status lists every watch, and one watch by id", async (t) => {
  const { call } = setup(t, runUntilCancelled);
  await call({ action: "start", id: "watch-a", condition: "false" });
  await call({ action: "start", id: "watch-b", intervalSec: 5, maxTicks: 2 });

  const all = await call({ action: "status" });
  assert.match(all.content[0].text, /^watch-a {2}running {2}\d+s {2}ticks 0\/unlimited {2}cond: false\nwatch-b {2}running {2}\d+s {2}ticks 0\/2 {2}timer, no condition$/);

  const one = await call({ action: "status", id: "watch-b" });
  assert.match(one.content[0].text, /^watch-b {2}running/);
});

test("resuming a session restores its active watches", async (t) => {
  const { hooks, call, noticesAfter, branch } = setup(t, () => exit(0));
  const job = {
    action: "start",
    id: "restored-watch",
    condition: "true",
    intervalSec: 60,
    maxTicks: 0,
    timeoutSec: 60,
    startedAt: Date.now(),
  };

  await hooks.get("session_start")({}, branch(job));
  const [notice] = await noticesAfter(1);

  assert.equal(notice.details.id, "restored-watch");
  assert.match(notice.content, /condition met/);
});

test("watches already stopped on the branch are not restarted", async (t) => {
  const { hooks, call, branch } = setup(t, runUntilCancelled);
  const job = {
    action: "start",
    id: "watch-a",
    condition: "false",
    intervalSec: 60,
    timeoutSec: 60,
    startedAt: Date.now(),
  };

  await hooks.get("session_start")(
    {},
    branch(job, { action: "stop", id: "watch-a" }),
  );

  const status = await call({ action: "status" });
  assert.equal(status.content[0].text, "No active watches.");
});

test("a watch armed by the previous tool version is not restored", async (t) => {
  const { hooks, call, branch } = setup(t, runUntilCancelled);
  // The old tool stored `command`/`tailCommand`; its payload no longer exists.
  const legacy = {
    action: "start",
    id: "job-1",
    command: "false",
    tailCommand: "tail log",
    intervalSec: 60,
    timeoutSec: 60,
    startedAt: Date.now(),
  };

  await hooks.get("session_start")({}, branch(legacy));

  const status = await call({ action: "status" });
  assert.equal(status.content[0].text, "No active watches.");
});

test("a watch can still be stopped after the branch is restored again", async (t) => {
  const { hooks, call, branch } = setup(t, runUntilCancelled);
  const { details } = await call({
    action: "start",
    id: "watch-a",
    condition: "false",
  });

  await hooks.get("session_tree")({}, branch(details));
  await new Promise(setImmediate);

  const stop = await call({ action: "stop", id: "watch-a" });
  assert.equal(stop.content[0].text, 'Stopped "watch-a".');
});
