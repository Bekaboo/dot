import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import timerExtension from "../extensions/timer.ts";

// Job logs go under the agent dir; keep them out of the real one.
const agentDir = mkdtempSync(join(tmpdir(), "pi-timer-tests-"));
process.env.PI_CODING_AGENT_DIR = agentDir;
after(() => rmSync(agentDir, { recursive: true, force: true }));

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

test("a timed-out timer says so and can then be stopped", async (t) => {
  const { hooks, stop, noticesAfter, branch } = setup(t, () => exit(1));
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

  const stopped = await stop({ id: "stale-timer" });
  assert.equal(
    stopped.content[0].text,
    'Timer "stale-timer" stopped (timed out).',
  );
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
  const { start, stop, noticesAfter } = setup(t, () => exit(1));

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
});

test("a timer whose condition throws reports the failure and stops", async (t) => {
  const { start, stop, noticesAfter } = setup(t, () => {
    throw new Error("boom");
  });

  await start({ id: "broken-cond", condition: "snap", maxTicks: 0 });
  const [notice] = await noticesAfter(1);

  assert.match(notice.content, /^\[timer broken-cond\] error: Error: boom; timer stopped$/);
  assert.equal(
    (await stop({ id: "broken-cond" })).content[0].text,
    'Timer "broken-cond" stopped (failed).',
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

test("a throttled tick costs no budget, so the next wake still comes", async (t) => {
  const { start, notices, noticesAfter, hooks } = setup(t, () => exit(1), {
    ack: false,
  });

  await start({
    id: "busy-timer",
    intervalSec: 1,
    maxTicks: 2,
    timeoutSec: 6,
  });
  const [first] = await noticesAfter(1);
  assert.match(first.content, /tick 1\/2/);

  // The second fire lands while the first wake is still unread, so it is
  // dropped: it must neither send a wake nor spend the tick budget.
  await wait(1_200);
  assert.equal(notices.length, 1);

  // Once the agent acts on the wake, the budget must still hold one tick.
  await hooks.get("tool_call")({});
  const [, second] = await noticesAfter(2);

  assert.match(second.content, /tick 2\/2, \d+s elapsed; timer stopped$/);
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
  assert.match(result.content[0].text, /^Started "quiet-timer": no ticks; /);
});

test("status lists every timer, one timer by id, and rejects an unknown id", async (t) => {
  const { start, status } = setup(t, runUntilCancelled);
  await start({ id: "timer-a", condition: "false" });
  await start({ id: "timer-b", intervalSec: 5, maxTicks: 2 });

  const all = (await status({})).content[0].text;
  assert.match(all, /^timer-a +running .*ticks 0\/unlimited +cond: false$/m);
  assert.match(all, /^timer-b +running .*ticks 0\/2 +timer, no condition$/m);

  const one = (await status({ id: "timer-b" })).content[0].text;
  assert.match(one, /^timer-b +running .*ticks 0\/2/m);

  const unknown = (await status({ id: "ghost" })).content[0].text;
  assert.equal(unknown, 'No timer "ghost"; active: timer-a, timer-b.');
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

test("restoring a branch leaves exactly one poll loop per timer", async (t) => {
  let captures = 0;
  const { hooks, start, branch } = setup(t, (command) => {
    if (command === "snap") {
      captures += 1;
      return exit(0);
    }
    return exit(1);
  });
  const { details } = await start({
    id: "timer-a",
    onTick: "snap",
    intervalSec: 1,
    maxTicks: 5,
    timeoutSec: 30,
  });

  // Replaying the same start must replace the running loop, not add to it: a
  // stale poller would keep capturing for a timer nobody can stop.
  await hooks.get("session_tree")({}, branch(details));
  const before = captures;
  await wait(1_200);

  assert.equal(captures - before, 1);
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
    "start",
    "timeoutSec",
  ]);
  assert.deepEqual(Object.keys(tools.get("timer_stop").parameters.properties), [
    "id",
  ]);
  assert.deepEqual(Object.keys(tools.get("timer_status").parameters.properties), [
    "id",
  ]);
});

test("start runs a command and wakes with its exit code and log tail", async (t) => {
  const { start, noticesAfter } = setup(t, runUntilCancelled);

  const result = await start({ id: "job-a", start: "echo hello" });
  const [notice] = await noticesAfter(1);

  assert.equal(
    notice.content,
    "[timer job-a] exited 0 after 0s; timer stopped\nhello\n[exit 0]",
  );
  assert.equal(notice.details.state, "done");
  assert.equal(result.details.start, "echo hello");
  assert.equal(result.details.maxTicks, 0);
  assert.equal(result.details.timeoutSec, 86_400);
  assert.match(result.details.logPath, /\/jobs\/job-a-\d+\.log$/);
  assert.match(
    result.content[0].text,
    /^Started job "job-a": runs `echo hello` in the background, no tick wakes, log .*\/jobs\/job-a-\d+\.log; wakes you when it exits or after 86400s\. It is killed when this session ends\.$/,
  );
});

test("a failing command reports its exit code", async (t) => {
  const { start, noticesAfter } = setup(t, runUntilCancelled);

  await start({ id: "job-b", start: "echo nope >&2; exit 3" });
  const [notice] = await noticesAfter(1);

  assert.match(
    notice.content,
    /^\[timer job-b\] failed: exit 3 after \ds; timer stopped\nnope\n\[exit 3\]$/,
  );
});

test("start and condition are mutually exclusive", async (t) => {
  const { start } = setup(t, runUntilCancelled);

  await assert.rejects(
    start({ id: "job-c", start: "true", condition: "false" }),
    /start and condition are mutually exclusive/,
  );
});

test("stopping a job timer kills the job and sends no wake", async (t) => {
  const { start, stop, notices } = setup(t, runUntilCancelled);

  await start({ id: "job-d", start: "sleep 30" });
  const stopped = await stop({ id: "job-d" });

  assert.match(
    stopped.content[0].text,
    /^Stopped "job-d"; killed its job, log .*\/jobs\/job-d-\d+\.log\.$/,
  );
  await wait(300);
  assert.deepEqual(notices, []);
});

test("a job timer that times out kills the job", async (t) => {
  const { start, noticesAfter } = setup(t, runUntilCancelled);

  await start({ id: "job-e", start: "sleep 30", timeoutSec: 1 });
  const [notice] = await noticesAfter(1);

  assert.equal(
    notice.content,
    "[timer job-e] timeout after 1s; job killed; timer stopped\n[killed by the timer]",
  );
  assert.equal(notice.details.state, "timeout");
});

test("a replayed job from an earlier process is reported as orphaned", async (t) => {
  const { hooks, status, notices, branch } = setup(t, runUntilCancelled);
  const spec = {
    action: "start",
    id: "job-f",
    start: "sleep 1",
    logPath: "/tmp/gone/job-f.log",
    intervalSec: 60,
    maxTicks: 0,
    timeoutSec: 600,
    startedAt: Date.now(),
  };

  await hooks.get("session_start")({}, branch(spec));
  await wait(100);

  assert.deepEqual(notices, []);
  assert.equal(
    (await status({ id: "job-f" })).content[0].text,
    'Timer "job-f" stopped (orphaned; log /tmp/gone/job-f.log).',
  );
});

test("restoring a branch re-attaches a live job instead of running it twice", async (t) => {
  const { hooks, start, noticesAfter, branch } = setup(t, runUntilCancelled);
  const { details } = await start({ id: "job-g", start: "echo once; sleep 0.3" });

  await hooks.get("session_tree")({}, branch(details));
  const [notice] = await noticesAfter(1);

  assert.match(notice.content, /^\[timer job-g\] exited 0 after \ds; timer stopped\nonce/);
  const log = readFileSync(details.logPath, "utf8");
  assert.equal(log.match(/\[exit 0\]/g).length, 1);
});

test("status reports a running job's pid and log path", async (t) => {
  const { start, status, stop } = setup(t, runUntilCancelled);
  await start({ id: "job-h", start: "sleep 30" });

  const listed = (await status({ id: "job-h" })).content[0].text;
  assert.match(
    listed,
    /^job-h {2}running {2}\d+s {2}ticks 0\/0 {2}job pid \d+, log .*\/jobs\/job-h-\d+\.log$/,
  );
  await stop({ id: "job-h" });
});
