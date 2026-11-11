import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import timerExtension from "../extensions/timer.ts";

// Job logs go under the agent dir; keep them out of the real one.
const agentDir = mkdtempSync(join(tmpdir(), "pi-timer-jobs-tests-"));
process.env.PI_CODING_AGENT_DIR = agentDir;
after(() => rmSync(agentDir, { recursive: true, force: true }));

/** A command result, in the shape `pi.exec()` returns. */
const exit = (code, stdout = "") => ({ code, stdout, stderr: "" });

/**
 * Load the extension with a fake `pi`.
 *
 * @param runCommand - Fake shell for `condition` and `onTick` only; `start`
 *   jobs spawn a real bash, so these tests use real short commands.
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

/** Resolve after `ms` milliseconds, so a poll loop can reach its next tick. */
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Read a running job's pid from its `timer_status` line.
 *
 * @param status - The setup `status` caller.
 * @param id - Timer id of a running job.
 * @returns The job's process group leader pid.
 */
async function jobPid(status, id) {
  const listed = (await status({ id })).content[0].text;
  return Number(listed.match(/job pid (\d+)/)[1]);
}

/**
 * Wait until a signalled pid is gone, outlasting the SIGTERM grace period.
 *
 * @param pid - Process that should have been killed.
 */
async function waitGone(pid) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      process.kill(pid, 0);
    } catch {
      return;
    }
    await wait(100);
  }
  assert.fail(`process ${pid} is still alive`);
}

test("a job that exits 0 wakes with its output and the exit marker", async (t) => {
  const { start, noticesAfter } = setup(t, () => exit(1));

  const result = await start({ id: "job-ok", start: "echo hi" });
  const [notice] = await noticesAfter(1);

  assert.match(
    notice.content,
    /^\[timer job-ok\] exited 0 after \ds; timer stopped\nhi\n\[exit 0\]$/,
  );
  assert.equal(notice.details.state, "done");
  assert.equal(result.details.maxTicks, 0);
  assert.equal(result.details.timeoutSec, 86_400);
  // The log outlives the wake, so it must record the outcome too.
  assert.equal(readFileSync(result.details.logPath, "utf8"), "hi\n[exit 0]\n");
});

test("a job that exits non-zero wakes with failed: exit 3", async (t) => {
  const { start, noticesAfter } = setup(t, () => exit(1));

  const result = await start({ id: "job-fail", start: "exit 3" });
  const [notice] = await noticesAfter(1);

  assert.match(
    notice.content,
    /^\[timer job-fail\] failed: exit 3 after \ds; timer stopped\n\[exit 3\]$/,
  );
  assert.equal(readFileSync(result.details.logPath, "utf8"), "[exit 3]\n");
});

test("a command that never runs is reported as a failure, not success", async (t) => {
  const { start, noticesAfter } = setup(t, () => exit(1));

  await start({ id: "job-missing", start: "nonexistent-command-xyz" });
  const [notice] = await noticesAfter(1);

  // bash runs, but the command does not: exit 127 must not look like success.
  assert.match(
    notice.content,
    /^\[timer job-missing\] failed: exit 127 after \ds; timer stopped/,
  );
  assert.doesNotMatch(notice.content, /exited 0/);
});

test("a job timeout kills the job and marks the log", async (t) => {
  const { start, status, noticesAfter } = setup(t, () => exit(1));

  const result = await start({ id: "job-timeout", start: "sleep 30", timeoutSec: 1 });
  const pid = await jobPid(status, "job-timeout");
  const [notice] = await noticesAfter(1);

  assert.equal(
    notice.content,
    "[timer job-timeout] timeout after 1s; job killed; timer stopped\n[killed by the timer]",
  );
  assert.equal(notice.details.state, "timeout");
  assert.match(
    readFileSync(result.details.logPath, "utf8"),
    /\[killed by the timer\]\n$/,
  );
  await waitGone(pid);
  assert.throws(() => process.kill(pid, 0), { code: "ESRCH" });
});

test("timer_stop kills the job, says so, and sends no wake", async (t) => {
  const { start, stop, status, notices } = setup(t, () => exit(1));

  const result = await start({ id: "job-stop", start: "sleep 30" });
  const pid = await jobPid(status, "job-stop");
  const stopped = await stop({ id: "job-stop" });

  assert.equal(
    stopped.content[0].text,
    `Stopped "job-stop"; killed its job, log ${result.details.logPath}.`,
  );
  await waitGone(pid);
  assert.throws(() => process.kill(pid, 0), { code: "ESRCH" });
  assert.match(
    readFileSync(result.details.logPath, "utf8"),
    /\[killed by timer_stop\]\n$/,
  );
  // The exit the kill causes must not wake the agent: it asked for the stop.
  await wait(300);
  assert.deepEqual(notices, []);
});

test("session shutdown kills a running job", async (t) => {
  const { hooks, start, status } = setup(t, () => exit(1));

  await start({ id: "job-shutdown", start: "sleep 30" });
  const pid = await jobPid(status, "job-shutdown");

  await hooks.get("session_shutdown")({});

  await waitGone(pid);
  assert.throws(() => process.kill(pid, 0), { code: "ESRCH" });
});

test("the exit wake carries only the last 10 log lines", async (t) => {
  const { start, noticesAfter } = setup(t, () => exit(1));

  await start({ id: "job-tail", start: "seq 1 30" });
  const [notice] = await noticesAfter(1);

  // The marker counts as a line, so the tail is lines 22-30 plus [exit 0].
  assert.match(
    notice.content,
    /\n22\n23\n24\n25\n26\n27\n28\n29\n30\n\[exit 0\]$/,
  );
  assert.doesNotMatch(notice.content, /^21$/m);
  assert.equal(notice.content.split("\n").length, 11);
});

test("onTick output follows the log tail in the exit wake", async (t) => {
  const { start, noticesAfter } = setup(t, (command) =>
    command === "snap" ? exit(0, "snapshot") : exit(1),
  );

  await start({ id: "job-ontick", start: "echo hi", onTick: "snap" });
  const [notice] = await noticesAfter(1);

  assert.match(
    notice.content,
    /^\[timer job-ontick\] exited 0 after \ds; timer stopped\nhi\n\[exit 0\]\nsnapshot$/,
  );
});

test("restoring a start spec with no live job retires it as orphaned", async (t) => {
  const { hooks, status, notices, branch } = setup(t, () => exit(1));
  const spec = {
    action: "start",
    id: "job-orphan",
    start: "sleep 1",
    logPath: join(agentDir, "jobs", "gone.log"),
    intervalSec: 60,
    maxTicks: 0,
    timeoutSec: 600,
    startedAt: Date.now(),
  };

  await hooks.get("session_start")({}, branch(spec));
  await wait(100);

  assert.deepEqual(notices, []);
  assert.equal(
    (await status({ id: "job-orphan" })).content[0].text,
    `Timer "job-orphan" stopped (orphaned; log ${spec.logPath}).`,
  );
});

test("restoring a branch re-attaches a live job without rerunning it", async (t) => {
  const runsPath = join(agentDir, "job-reattach-runs.txt");
  const { hooks, start, notices, noticesAfter, branch } = setup(t, () => exit(1));
  const { details } = await start({
    id: "job-reattach",
    start: `echo run >> '${runsPath}'; sleep 0.5`,
  });

  await hooks.get("session_tree")({}, branch(details));
  const [notice] = await noticesAfter(1);

  assert.match(
    notice.content,
    /^\[timer job-reattach\] exited 0 after \ds; timer stopped/,
  );
  // One line in the file and one marker in the log: the command ran once and
  // only one loop watched it to the end.
  assert.equal(readFileSync(runsPath, "utf8"), "run\n");
  assert.equal(
    readFileSync(details.logPath, "utf8").match(/\[exit 0\]/g).length,
    1,
  );
  await wait(100);
  assert.equal(notices.length, 1);
});

test("a job cannot also have a condition", async (t) => {
  const { start } = setup(t, () => exit(1));

  await assert.rejects(
    start({ id: "job-both", start: "true", condition: "false" }),
    /start and condition are mutually exclusive/,
  );
});

test("a job accepts maxTicks 0 and rejects a duplicate id", async (t) => {
  const { start, stop, noticesAfter } = setup(t, () => exit(1));

  const result = await start({ id: "job-zero", start: "echo hi", maxTicks: 0 });
  assert.equal(result.details.maxTicks, 0);
  assert.match(result.content[0].text, /no tick wakes/);
  await noticesAfter(1);

  await start({ id: "job-dup", start: "sleep 30" });
  await assert.rejects(
    start({ id: "job-dup", start: "echo hi" }),
    /already active/,
  );
  await stop({ id: "job-dup" });
});

test("a job timer with maxTicks 1 ticks once and still wakes on exit", async (t) => {
  const { start, notices, noticesAfter } = setup(t, () => exit(1));

  await start({
    id: "job-tick",
    start: "sleep 1.5",
    intervalSec: 1,
    maxTicks: 1,
    timeoutSec: 10,
  });
  await noticesAfter(2);
  await wait(100);

  assert.equal(notices.length, 2);
  assert.equal(notices[0].details.state, "tick");
  assert.match(notices[0].content, /^\[timer job-tick\] tick 1\/1, \ds elapsed$/);
  assert.equal(notices[1].details.state, "done");
  assert.match(
    notices[1].content,
    /^\[timer job-tick\] exited 0 after \ds; timer stopped/,
  );
});

test("a log deleted before the job exits does not crash the wake", async (t) => {
  const { start, noticesAfter } = setup(t, () => exit(1));

  const { details } = await start({ id: "job-nolog", start: "sleep 0.3" });
  rmSync(details.logPath);
  const [notice] = await noticesAfter(1);

  assert.match(
    notice.content,
    /^\[timer job-nolog\] exited 0 after \ds; timer stopped/,
  );
  assert.equal(notice.details.state, "done");
});
