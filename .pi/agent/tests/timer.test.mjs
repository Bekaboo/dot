import assert from "node:assert/strict";
import test from "node:test";

import timerExtension from "../extensions/timer.ts";

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
  const tools = new Map();
  const hooks = new Map();
  const notices = [];
  let onNotice = () => {};
  timerExtension({
    registerTool: (definition) => {
      tools.set(definition.name, definition);
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
  const call = (name, params) => tools.get(name).execute("test", params);
  const start = (params) => call("timer_start", params);
  const stop = (params) => call("timer_stop", params);
  const status = (params) => call("timer_status", params);
  /** Wait until the timer sends `count` notifications in total. */
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
          message: {
            role: "toolResult",
            toolName: detail.action === "stop" ? "timer_stop" : "timer_start",
            details: detail,
          },
        })),
    },
  });
  t.after(() => hooks.get("session_shutdown")({}));
  return { hooks, tools, call, start, stop, status, notices, noticesAfter, branch };
}

/** A fake shell whose commands keep running until the timer cancels them. */
function runUntilCancelled(_command, signal) {
  return new Promise((resolve) =>
    signal.addEventListener("abort", () => resolve(exit(null))),
  );
}

/** Resolve after `ms` milliseconds, so a poll loop can reach its next tick. */
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

test("a timer wakes with 'condition met' as soon as its condition holds", async (t) => {
  const { start, noticesAfter } = setup(t, () => exit(0));

  const result = await start({
    id: "build-done",
    condition: "test -f done",
    maxTicks: 0,
  });
  const [notice] = await noticesAfter(1);

  assert.equal(result.details.id, "build-done");
  assert.equal(
    notice.content,
    "[timer build-done] condition met after 0s: test -f done; timer stopped",
  );
  assert.equal(notice.details.state, "done");
  assert.equal(notice.options.deliverAs, "steer");
});

test("a timer reports a timeout when its deadline passes", async (t) => {
  const { hooks, noticesAfter, branch } = setup(t, () => exit(1));
  // A timer whose time ran out while the session was closed.
  const expired = {
    action: "start",
    id: "stale-timer",
    condition: "false",
    intervalSec: 1,
    maxTicks: 0,
    timeoutSec: 1,
    startedAt: Date.now() - 2_000,
  };

  await hooks.get("session_start")({}, branch(expired));
  const [notice] = await noticesAfter(1);

  assert.equal(
    notice.content,
    "[timer stale-timer] timeout after 1s; timer stopped",
  );
  assert.equal(notice.details.state, "timeout");
});

test("stopping an unknown timer lists the active ones", async (t) => {
  const { start, stop } = setup(t, runUntilCancelled);
  await start({ id: "timer-a", condition: "false" });
  await start({ id: "timer-b", condition: "false" });

  await assert.rejects(
    stop({ id: "timer-c" }),
    /No timer "timer-c"; active: timer-a, timer-b\./,
  );
  const stopped = await stop({ id: "timer-a" });
  assert.equal(stopped.content[0].text, 'Stopped "timer-a".');
});

test("start rejects a missing id, a nameless timer, and a bad id", async (t) => {
  const { start } = setup(t, runUntilCancelled);

  await assert.rejects(start({}), /timer id is required/);
  await assert.rejects(
    start({ id: "peek-1", intervalSec: 1, maxTicks: 0 }),
    /could never wake you/,
  );
  await assert.rejects(
    start({ id: "bad id!", condition: "false" }),
    /Invalid timer id/,
  );
});

test("start rejects a duplicate id and an unreachable tick", async (t) => {
  const { start } = setup(t, runUntilCancelled);
  await start({ id: "timer-a", condition: "false" });

  await assert.rejects(
    start({ id: "timer-a", condition: "false" }),
    /already active/,
  );
  await assert.rejects(
    start({
      id: "timer-b",
      intervalSec: 30,
      timeoutSec: 10,
      maxTicks: 1,
    }),
    /cannot tick/,
  );
});

test("a one-shot timer wakes once, says it stopped, then retires itself", async (t) => {
  const { start, stop, status, noticesAfter } = setup(t, () => exit(1));

  await start({
    id: "peek-1",
    intervalSec: 1,
    maxTicks: 1,
    timeoutSec: 90,
  });
  const [notice] = await noticesAfter(1);

  assert.match(
    notice.content,
    /^\[timer peek-1\] tick 1\/1, \ds elapsed; timer stopped$/,
  );
  await wait(50);

  // The agent stops a timer it just saw finish; that must not look like a bug.
  const stopped = await stop({ id: "peek-1" });
  assert.equal(
    stopped.content[0].text,
    'Timer "peek-1" stopped (tick budget spent).',
  );
  assert.equal(
    (await status({ id: "peek-1" })).content[0].text,
    'Timer "peek-1" stopped (tick budget spent).',
  );

  // An id that never ran is still a real mistake.
  await assert.rejects(stop({ id: "never-ran" }), /No timer "never-ran"/);
});

test("stopping a timed-out timer reports that it stopped", async (t) => {
  const { hooks, stop, noticesAfter, branch } = setup(t, () => exit(1));
  const expired = {
    action: "start",
    id: "stale-timer",
    condition: "false",
    intervalSec: 1,
    maxTicks: 0,
    timeoutSec: 1,
    startedAt: Date.now() - 2_000,
  };

  await hooks.get("session_start")({}, branch(expired));
  await noticesAfter(1);

  const stopped = await stop({ id: "stale-timer" });
  assert.equal(
    stopped.content[0].text,
    'Timer "stale-timer" stopped (timed out).',
  );
});

test("only recent stopped timers are remembered", async (t) => {
  const { start, stop, noticesAfter } = setup(t, () => exit(0));

  // A condition that already holds ends each timer on its first check, so this
  // needs no tick interval.
  for (let index = 0; index < 12; index += 1) {
    await start({ id: `peek-${index}`, condition: "true", maxTicks: 0 });
    await noticesAfter(index + 1);
  }

  // The history is bounded, so the oldest id is forgotten and errors again.
  await assert.rejects(stop({ id: "peek-0" }), /No timer "peek-0"/);
  assert.equal(
    (await stop({ id: "peek-11" })).content[0].text,
    'Timer "peek-11" stopped (condition met).',
  );
});

test("reusing a retired id starts a fresh timer", async (t) => {
  const { start, stop, status, noticesAfter } = setup(t, () => exit(1));

  await start({ id: "peek-1", intervalSec: 1, maxTicks: 1, timeoutSec: 5 });
  await noticesAfter(1);
  await wait(50);

  await start({ id: "peek-1", intervalSec: 5, maxTicks: 2, timeoutSec: 60 });

  assert.match((await status({ id: "peek-1" })).content[0].text, /^peek-1 {2}running/);
  assert.equal(
    (await stop({ id: "peek-1" })).content[0].text,
    'Stopped "peek-1".',
  );
});

test("a timer ticks exactly maxTicks times", async (t) => {
  const { start, notices } = setup(t, () => exit(1));

  await start({
    id: "monitor-1",
    intervalSec: 1,
    maxTicks: 2,
    timeoutSec: 10,
  });
  await wait(2_400);

  assert.equal(notices.length, 2);
  assert.match(notices[0].content, /^\[timer monitor-1\] tick 1\/2, \d+s elapsed$/);
  // Only the last tick may announce the end, so the first stays plain.
  assert.match(
    notices[1].content,
    /^\[timer monitor-1\] tick 2\/2, \d+s elapsed; timer stopped$/,
  );
});

test("a tick is dropped while the previous one is still unread", async (t) => {
  const { start, notices, hooks } = setup(t, () => exit(1), { ack: false });

  await start({
    id: "busy-timer",
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

test("onTick output rides along with a wake", async (t) => {
  const { start, noticesAfter } = setup(t, (command) =>
    command === "tail log" ? exit(0, "build finished") : exit(1),
  );

  await start({
    id: "build-timer",
    condition: "test -f done",
    onTick: "tail log",
    intervalSec: 1,
    maxTicks: 1,
    timeoutSec: 5,
  });
  const [notice] = await noticesAfter(1);

  assert.match(
    notice.content,
    /^\[timer build-timer\] tick 1\/1, \d+s elapsed\nbuild finished$/,
  );
});

test("a throttled tick still runs onTick but sends no wake", async (t) => {
  let captures = 0;
  const { start, notices } = setup(
    t,
    (command) => {
      if (command !== "snap") {
        return exit(1);
      }
      captures += 1;
      return exit(0, "snapshot");
    },
    { ack: false },
  );

  await start({
    id: "busy-timer",
    onTick: "snap",
    intervalSec: 1,
    maxTicks: 2,
    timeoutSec: 10,
  });
  await wait(2_300);

  assert.equal(notices.length, 1);
  assert.equal(captures, 2);
});

test("onTick may produce no output", async (t) => {
  const { start, noticesAfter } = setup(t, (command) =>
    command === "true" ? exit(0) : exit(1),
  );

  await start({
    id: "silent-work",
    onTick: "true",
    intervalSec: 1,
    maxTicks: 1,
    timeoutSec: 5,
  });
  const [notice] = await noticesAfter(1);

  // No body line: empty callback output must not leave a dangling newline.
  assert.match(
    notice.content,
    /^\[timer silent-work\] tick 1\/1, \d+s elapsed; timer stopped$/,
  );
});

test("onTick output is capped", async (t) => {
  const many = Array.from({ length: 60 }, (_, index) => `line ${index}`).join(
    "\n",
  );
  const { start, noticesAfter } = setup(t, (command) =>
    command === "snap" ? exit(0, many) : exit(1),
  );

  await start({
    id: "noisy-timer",
    onTick: "snap",
    intervalSec: 1,
    maxTicks: 1,
    timeoutSec: 5,
  });
  const [notice] = await noticesAfter(1);

  assert.match(notice.content, /line 39\n\.\.\. \(\+20 more lines\)$/);
  assert.doesNotMatch(notice.content, /line 40/);
});

test("a failing onTick does not kill the timer", async (t) => {
  const { start, noticesAfter } = setup(t, (command) => {
    if (command === "snap") {
      throw new Error("boom");
    }
    return exit(1);
  });

  await start({
    id: "broken-timer",
    onTick: "snap",
    intervalSec: 1,
    maxTicks: 1,
    timeoutSec: 5,
  });
  const [notice] = await noticesAfter(1);

  assert.match(notice.content, /tick 1\/1.*\nonTick failed: Error: boom$/);
});

test("maxTicks 0 silences a condition timer until it finishes", async (t) => {
  const { start, notices } = setup(t, () => exit(1));

  const result = await start({
    id: "quiet-timer",
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
    result.content[0].text,
    'Started "quiet-timer": no ticks; it ends when the condition first exits 0 or after 5s. Wakes arrive even after you end your turn.',
  );
});

test("status lists every timer, and one timer by id", async (t) => {
  const { start, status } = setup(t, runUntilCancelled);
  await start({ id: "timer-a", condition: "false" });
  await start({ id: "timer-b", intervalSec: 5, maxTicks: 2 });

  const all = await status({});
  assert.match(all.content[0].text, /^timer-a {2}running {2}\d+s {2}ticks 0\/unlimited {2}cond: false\ntimer-b {2}running {2}\d+s {2}ticks 0\/2 {2}timer, no condition$/);

  const one = await status({ id: "timer-b" });
  assert.match(one.content[0].text, /^timer-b {2}running/);
});

test("resuming a session restores its active timers", async (t) => {
  const { hooks, noticesAfter, branch } = setup(t, () => exit(0));
  const job = {
    action: "start",
    id: "restored-timer",
    condition: "true",
    intervalSec: 60,
    maxTicks: 0,
    timeoutSec: 60,
    startedAt: Date.now(),
  };

  await hooks.get("session_start")({}, branch(job));
  const [notice] = await noticesAfter(1);

  assert.equal(notice.details.id, "restored-timer");
  assert.match(notice.content, /condition met/);
});

test("restoring a session keeps the onTick callback", async (t) => {
  const { hooks, noticesAfter, branch } = setup(t, (command) =>
    command === "snap" ? exit(0, "restored snapshot") : exit(0),
  );
  const job = {
    action: "start",
    id: "restored-timer",
    condition: "true",
    onTick: "snap",
    intervalSec: 60,
    maxTicks: 0,
    timeoutSec: 60,
    startedAt: Date.now(),
  };

  await hooks.get("session_start")({}, branch(job));
  const [notice] = await noticesAfter(1);

  assert.match(notice.content, /condition met .*\nrestored snapshot$/);
});

test("timers already stopped on the branch are not restarted", async (t) => {
  const { hooks, status, branch } = setup(t, runUntilCancelled);
  const job = {
    action: "start",
    id: "timer-a",
    condition: "false",
    intervalSec: 60,
    timeoutSec: 60,
    startedAt: Date.now(),
  };

  await hooks.get("session_start")(
    {},
    branch(job, { action: "stop", id: "timer-a" }),
  );

  const listed = await status({});
  assert.equal(listed.content[0].text, "No active timers.");
});

test("entries from the previous watch tool are ignored", async (t) => {
  const { hooks, status } = setup(t, runUntilCancelled);
  // The old tool stored a payload and ran under another tool name.
  const legacy = {
    action: "start",
    id: "job-1",
    command: "false",
    tailCommand: "tail log",
    intervalSec: 60,
    timeoutSec: 60,
    startedAt: Date.now(),
  };
  const branch = {
    sessionManager: {
      getBranch: () => [
        {
          type: "message",
          message: {
            role: "toolResult",
            toolName: "watch",
            details: legacy,
          },
        },
      ],
    },
  };

  await hooks.get("session_start")({}, branch);

  const listed = await status({});
  assert.equal(listed.content[0].text, "No active timers.");
});

test("a timer can still be stopped after the branch is restored again", async (t) => {
  const { hooks, start, stop, branch } = setup(t, runUntilCancelled);
  const { details } = await start({
    id: "timer-a",
    condition: "false",
  });

  await hooks.get("session_tree")({}, branch(details));
  await new Promise(setImmediate);

  const stopped = await stop({ id: "timer-a" });
  assert.equal(stopped.content[0].text, 'Stopped "timer-a".');
});

test("the extension registers one tool per action", (t) => {
  const { tools } = setup(t, runUntilCancelled);

  assert.deepEqual([...tools.keys()], [
    "timer_start",
    "timer_stop",
    "timer_status",
  ]);
  assert.deepEqual(Object.keys(tools.get("timer_start").parameters.properties).sort(), [
    "condition",
    "id",
    "intervalSec",
    "maxTicks",
    "onTick",
    "timeoutSec",
  ]);
  assert.deepEqual(Object.keys(tools.get("timer_stop").parameters.properties), [
    "id",
  ]);
  assert.deepEqual(Object.keys(tools.get("timer_status").parameters.properties), [
    "id",
  ]);
});
