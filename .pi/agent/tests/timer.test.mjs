import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import {
  closeSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";
import {
  DEFAULT_MAX_BYTES,
  DEFAULT_MAX_LINES,
} from "@earendil-works/pi-coding-agent";
import timerExtension, {
  DEFAULT_TIMEOUT_SEC,
  JOB_TAIL_LINES,
  jobScript,
  RETIRED_HISTORY,
  SELECTED_CURSOR,
} from "../extensions/timer.ts";
import { VIEWPORT_RESERVE_ROWS } from "../extensions/utils/page.ts";

const { KeybindingsManager, TUI_KEYBINDINGS } = await import(
  "@earendil-works/pi-tui"
);

// A pid no process can hold, for state files of jobs that are already gone.
const DEAD_PID = 4_194_304;

// Job logs go under the agent dir; keep them out of the real one.
const agentDir = mkdtempSync(join(tmpdir(), "pi-timer-tests-"));
process.env.PI_CODING_AGENT_DIR = agentDir;
after(() => rmSync(agentDir, { recursive: true, force: true }));

/** A command result, in the shape `pi.exec()` returns. */
const exit = (code, stdout = "") => ({ code, stdout, stderr: "" });

/**
 * The body of a timer wake, after its one-line summary.
 *
 * @param content - Wake content.
 * @returns Everything after the summary paragraph, or an empty string.
 */
function wakeBody(content) {
  const split = content.indexOf("\n\n");
  return split === -1 ? "" : content.slice(split + 2);
}

/**
 * The callback preview in a wake, without its full-output notice.
 *
 * @param content - Wake content.
 * @returns The preview block.
 */
function wakePreview(content) {
  return wakeBody(content).split("\n\n[Showing ")[0];
}

/**
 * Split the job stdin prefix the timer adds for job callbacks.
 *
 * @param command - Shell command handed to the fake `pi.exec()`.
 * @returns The command without the prefix, and the log content it would read
 *   on stdin, or `undefined` when the command has no job input.
 */
function splitJobInput(command) {
  const match = /^\{ exec 0<(.+?); \} 2>\/dev\/null; /s.exec(command);
  if (!match) return { command, stdin: undefined };
  const path = match[1].slice(1, -1).replace(/'\\''/g, "'");
  return {
    command: command.slice(match[0].length),
    stdin: existsSync(path) ? readFileSync(path, "utf8") : "",
  };
}

/**
 * Load the extension with a fake `pi`.
 *
 * @param t - Test context, used to shut the session down afterwards.
 * @param runCommand - Fake shell for `condition` and `onTick`; `start` jobs
 *   spawn a real bash instead.
 * @param options - `ack: false` leaves wakes unread, to test coalescing;
 *   `sessionId` shares one session's state file between two pi processes.
 * @returns Handles for the registered tools, hooks, and captured notices.
 */
function setup(t, runCommand, { ack = true, sessionId = randomUUID() } = {}) {
  const tools = new Map();
  const hooks = new Map();
  const commands = new Map();
  const notices = [];
  const notified = [];
  let onNotice = () => {};
  timerExtension({
    registerTool: (definition) => {
      tools.set(definition.name, definition);
    },
    registerCommand: (name, definition) => {
      commands.set(name, definition);
    },
    on: (name, handler) => hooks.set(name, handler),
    exec: async (_bash, [_flag, command], { signal }) => {
      const { command: shell, stdin } = splitJobInput(command);
      return runCommand(shell, signal, stdin);
    },
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
      getSessionId: () => sessionId,
      getHeader: () => null,
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
    ui: { notify: (text) => notified.push(text) },
  });
  t.after(() => hooks.get("session_shutdown")({}));
  return {
    hooks,
    tools,
    commands,
    start,
    stop,
    status,
    notices,
    notified,
    noticesAfter,
    branch,
    sessionId,
  };
}

/** Absolute path of one session's timer state file. */
function stateFileOf(sessionId) {
  return join(agentDir, "timers", `${sessionId}.json`);
}

/** Write a timer state file, as a previous pi process would have left it. */
function writeState(sessionId, timers) {
  mkdirSync(join(agentDir, "timers"), { recursive: true });
  writeFileSync(
    stateFileOf(sessionId),
    `${JSON.stringify({
      version: 1,
      sessionId,
      updatedAt: Date.now(),
      timers,
    })}\n`,
  );
}

/** A timer record for `writeState`, with a budget already partly spent. */
function persistedTimer(id, { activeMs = 0, job, ...spec } = {}) {
  return {
    id,
    intervalSec: 1,
    timeoutSec: 600,
    startedAt: Date.now(),
    ticksSent: 0,
    ...spec,
    activeMs,
    job,
  };
}

/** A fake shell whose commands keep running until the timer cancels them. */
function runUntilCancelled(_command, signal) {
  return new Promise((resolve) =>
    signal.addEventListener("abort", () => resolve(exit(null))),
  );
}

/** Theme that adds no attributes, so tests read the page as plain text. */
const flatTheme = {
  fg: (_color, text) => text,
  bold: (text) => text,
  bg: (_color, text) => text,
};

/**
 * A fake extension UI that opens a custom component like the TUI mode does.
 *
 * @param t - Node test context, used to dispose a component left open.
 * @param options - `rows` for a short terminal, `theme` to record color use.
 * @returns The fake UI and the component it opened.
 */
function fakeUI(t, { rows = 40, theme = flatTheme } = {}) {
  let component;
  const tui = { requestRender() {}, terminal: { rows } };
  t.after(() => component?.dispose?.());
  return {
    get component() {
      return component;
    },
    ui: {
      notify: () => assert.fail("TUI mode must not notify"),
      custom(factory) {
        return new Promise((resolve) => {
          const done = (result) => {
            const closing = component;
            component = undefined;
            closing?.dispose?.();
            resolve(result);
          };
          const keybindings = new KeybindingsManager(TUI_KEYBINDINGS, {});
          component = factory(tui, theme, keybindings, done);
        });
      },
    },
  };
}

/**
 * The page as the user reads it, rows without the selection cursor.
 *
 * @param overlay - Open `/timers` overlay.
 * @param width - Overlay width.
 * @returns The rendered page, one line per row.
 */
function pageOf(overlay, width = 100) {
  return overlay
    .render(width)
    .map((line) => line.replace(SELECTED_CURSOR, " "))
    .join("\n");
}

/**
 * A page split into trimmed lines, so a test can name one row exactly.
 *
 * @param text - Page text from `pageOf`.
 * @returns One trimmed line per page row.
 */
function linesOf(text) {
  return text.split("\n").map((line) => line.trim());
}

/** Resolve after `ms` milliseconds, so a poll loop can reach its next tick. */
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * A `timer_start` spec for a condition that never holds, so it keeps running.
 *
 * @param id - Timer id.
 * @param startedAt - When the branch recorded it as armed.
 * @returns Details of a start tool result.
 */
function armedSpec(id, startedAt) {
  return {
    action: "start",
    id,
    condition: "false",
    intervalSec: 1,
    maxTicks: 0,
    timeoutSec: 600,
    startedAt,
  };
}

/**
 * The ids the list shows, in the order it shows them, top to bottom.
 *
 * @param overlay - Open `/timers` overlay.
 * @param wanted - Ids to keep, in any order.
 * @returns One id per row whose id is in `wanted`.
 */
function listedIds(overlay, wanted) {
  return linesOf(pageOf(overlay))
    .map((line) => line.split(/ +/)[0])
    .filter((id) => wanted.includes(id));
}

/**
 * Wait until `check()` holds, so a timing test never depends on a fixed sleep.
 *
 * @param check - Predicate polled every 50ms.
 * @param message - Assertion message when the predicate never holds.
 */
async function until(check, message) {
  for (let attempt = 0; attempt < 200; attempt += 1) {
    if (check()) return;
    await wait(50);
  }
  assert.fail(message);
}

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
 * Spawn a detached job shell the way the extension does.
 *
 * Its own process group, a tag in the command line, and a log it closes with
 * the `[exit N]` marker. Used to stand in for a job an earlier pi process ran.
 *
 * @param command - Shell command for the job.
 * @param tag - Token the extension would use to recognize the job.
 * @returns The process, its pid, and the log it writes.
 */
function spawnJobShell(command, tag, timeoutSec = 600) {
  const logPath = join(agentDir, "jobs", `${tag}.log`);
  mkdirSync(join(agentDir, "jobs"), { recursive: true });
  const log = openSync(logPath, "a");
  const proc = spawn("bash", ["-c", jobScript(tag, command, timeoutSec)], {
    detached: true,
    stdio: ["ignore", log, log],
  });
  closeSync(log);
  return { proc, pid: Number(proc.pid), logPath };
}

/**
 * Spawn a job shell from a pi that predates the wrapper-owned deadline.
 *
 * It has the tag and the `[exit N]` line, but no watchdog, so only the
 * registry's backstop can end it.
 */
function spawnLegacyJobShell(command, tag) {
  const logPath = join(agentDir, "jobs", `${tag}.log`);
  mkdirSync(join(agentDir, "jobs"), { recursive: true });
  const log = openSync(logPath, "a");
  const proc = spawn(
    "bash",
    [
      "-c",
      [
        `# pi-timer-job ${tag}`,
        `(\n${command}\n)`,
        "code=$?",
        "printf '[exit %s]\\n' \"$code\"",
        'exit "$code"',
      ].join("\n"),
    ],
    { detached: true, stdio: ["ignore", log, log] },
  );
  closeSync(log);
  return { proc, pid: Number(proc.pid), logPath };
}

/** Kill a spawned job's process group when the test ends, whatever happened. */
function killGroupAfter(t, pid) {
  t.after(() => {
    try {
      process.kill(-pid, "SIGKILL");
    } catch {
      // Already gone.
    }
  });
}

/**
 * Wait until a process group is gone, e.g. after a KILL escalation.
 *
 * @param pgid - Process-group leader pid.
 */
async function waitGroupGone(pgid) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      process.kill(-pgid, 0);
    } catch {
      return;
    }
    await wait(100);
  }
  assert.fail(`process group ${pgid} is still alive`);
}

/** Whether a pid still exists. */
function pidAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
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

describe("timer", () => {
  test("a timer wakes with 'condition met' as soon as its condition holds", async (t) => {
    const { start, noticesAfter } = setup(t, (_command, _signal, stdin) => {
      // A timer without a job has no output to feed its condition.
      assert.equal(stdin, undefined);
      return exit(0);
    });

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
    // A branch replay has no live state file, so the budget starts fresh and
    // runs out one live second later.
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

  test("start rejects a missing id, a bad id, and a nameless timer", async (t) => {
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

  test("the extension registers one tool per action", (t) => {
    const { tools } = setup(t, runUntilCancelled);

    assert.deepEqual(
      [...tools.keys()],
      ["timer_start", "timer_stop", "timer_status"],
    );
    assert.deepEqual(
      Object.keys(tools.get("timer_start").parameters.properties).sort(),
      [
        "condition",
        "id",
        "intervalSec",
        "maxTicks",
        "onTick",
        "start",
        "timeoutSec",
      ],
    );
    // The default belongs to the schema, so the prompt need not repeat it.
    assert.equal(
      tools.get("timer_start").parameters.properties.timeoutSec.default,
      DEFAULT_TIMEOUT_SEC,
    );
    assert.deepEqual(
      Object.keys(tools.get("timer_stop").parameters.properties),
      ["id"],
    );
    assert.deepEqual(
      Object.keys(tools.get("timer_status").parameters.properties),
      ["id"],
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

    assert.match(
      notice.content,
      /^\[timer broken-cond\] error: Error: boom; timer stopped$/,
    );
    assert.equal(
      (await stop({ id: "broken-cond" })).content[0].text,
      'Timer "broken-cond" stopped (failed).',
    );
  });

  test("only recent stopped timers are remembered", async (t) => {
    const { start, stop, noticesAfter } = setup(t, () => exit(0));

    // A condition that already holds ends each timer on its first check, so this
    // needs no tick interval.
    const started = RETIRED_HISTORY + 2;
    for (let index = 0; index < started; index += 1) {
      await start({ id: `peek-${index}`, condition: "true", maxTicks: 0 });
      await noticesAfter(index + 1);
    }

    // The history is bounded, so the oldest id is forgotten and errors again.
    await assert.rejects(stop({ id: "peek-0" }), /No timer "peek-0"/);
    assert.equal(
      (await stop({ id: `peek-${started - 1}` })).content[0].text,
      `Timer "peek-${started - 1}" stopped (condition met).`,
    );
  });

  test("reusing a retired id starts a fresh timer", async (t) => {
    const { start, stop, status, noticesAfter } = setup(t, () => exit(1));

    await start({ id: "peek-1", intervalSec: 1, maxTicks: 1, timeoutSec: 5 });
    await noticesAfter(1);
    await wait(50);

    await start({ id: "peek-1", intervalSec: 5, maxTicks: 2, timeoutSec: 60 });

    assert.match(
      (await status({ id: "peek-1" })).content[0].text,
      /^peek-1 {2}running/,
    );
    assert.equal(
      (await stop({ id: "peek-1" })).content[0].text,
      'Stopped "peek-1".',
    );
  });

  test("a timer ticks exactly maxTicks times", async (t) => {
    const { start, notices, noticesAfter } = setup(t, () => exit(1));

    await start({
      id: "monitor-1",
      intervalSec: 1,
      maxTicks: 2,
      timeoutSec: 10,
    });
    await noticesAfter(2);
    // Settle briefly: a third tick would mean the budget was not honored.
    await wait(300);

    assert.equal(notices.length, 2);
    assert.match(
      notices[0].content,
      /^\[timer monitor-1\] tick 1\/2, \d+s elapsed$/,
    );
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
      /^\[timer build-timer\] tick 1\/1, \d+s elapsed\n\nbuild finished$/,
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
    await until(() => captures === 2, "onTick ran only once");
    // Settle briefly: the second fire had to send no wake.
    await wait(300);

    assert.equal(captures, 2);
    assert.equal(notices.length, 1);
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

  test("large onTick output is previewed and saved in full", async (t) => {
    const extra = 20;
    const many = Array.from(
      { length: DEFAULT_MAX_LINES + extra },
      (_, index) => `line ${index}`,
    ).join("\n");
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

    const saved = /Full output: (\/.*\.log)\]$/.exec(notice.content);
    assert.ok(saved, "the wake names the full output file");
    assert.equal(readFileSync(saved[1], "utf8"), many);
    assert.match(
      notice.content,
      new RegExp(`line ${DEFAULT_MAX_LINES + extra - 1}$`, "m"),
    );
    assert.doesNotMatch(notice.content, /^line 0$/m);
  });

  test("onTick output over the byte limit keeps a bounded tail", async (t) => {
    const line = "x".repeat(60);
    const many = Array.from(
      { length: Math.ceil(DEFAULT_MAX_BYTES / line.length) + 200 },
      (_, index) => `${index}:${line}`,
    ).join("\n");
    const { start, noticesAfter } = setup(t, (command) =>
      command === "snap" ? exit(0, many) : exit(1),
    );

    await start({
      id: "byte-limit",
      onTick: "snap",
      intervalSec: 1,
      maxTicks: 1,
      timeoutSec: 5,
    });
    const [notice] = await noticesAfter(1);

    const saved = /Full output: (\/.*\.log)\]$/.exec(notice.content);
    assert.ok(saved, "the wake names the full output file");
    assert.equal(readFileSync(saved[1], "utf8"), many);
    assert.ok(
      Buffer.byteLength(wakePreview(notice.content)) <= DEFAULT_MAX_BYTES,
    );
    assert.doesNotMatch(wakePreview(notice.content), /^0:/m);
  });

  test("one oversized onTick line keeps only its tail", async (t) => {
    const huge = "x".repeat(DEFAULT_MAX_BYTES + 1_000);
    const { start, noticesAfter } = setup(t, (command) =>
      command === "snap" ? exit(0, huge) : exit(1),
    );

    await start({
      id: "one-line",
      onTick: "snap",
      intervalSec: 1,
      maxTicks: 1,
      timeoutSec: 5,
    });
    const [notice] = await noticesAfter(1);

    const saved = /Full output: (\/.*\.log)\]$/.exec(notice.content);
    assert.ok(saved, "the wake names the full output file");
    assert.equal(readFileSync(saved[1], "utf8"), huge);
    const preview = wakePreview(notice.content);
    assert.ok(preview.length > 0);
    assert.ok(Buffer.byteLength(preview) <= DEFAULT_MAX_BYTES);
  });

  test("large onTick output is not spilled when no wake is sent", async (t) => {
    const many = Array.from(
      { length: DEFAULT_MAX_LINES + 1 },
      (_, index) => `line ${index}`,
    ).join("\n");
    let captures = 0;
    const { start, notices } = setup(t, (command) => {
      if (command !== "snap") return exit(1);
      captures += 1;
      return exit(0, many);
    });

    await start({
      id: "quiet-large",
      condition: "false",
      onTick: "snap",
      intervalSec: 1,
      maxTicks: 0,
      timeoutSec: 5,
    });
    await until(() => captures === 2, "onTick ran only once");

    assert.equal(notices.length, 0);
    const jobsDir = join(agentDir, "jobs");
    const files = existsSync(jobsDir) ? readdirSync(jobsDir) : [];
    assert.ok(
      !files.some((name) => name.startsWith("quiet-large-ontick-")),
      "a discarded tick must not leave an onTick output file",
    );
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

    assert.match(notice.content, /tick 1\/1.*\n\nonTick failed: Error: boom$/);
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

  test("/timers opens a live overlay showing active timers in aligned columns", async (t) => {
    const { start, commands } = setup(t, runUntilCancelled);
    const bolded = [];
    const colored = [];
    const screen = fakeUI(t, {
      theme: {
        fg: (color, text) => {
          colored.push({ color, text });
          return text;
        },
        bold: (text) => {
          bolded.push(text);
          return text;
        },
        bg: (_color, text) => text,
      },
    });
    const command = commands.get("timers");

    const showing = command.handler("", { mode: "tui", ui: screen.ui });
    const overlay = screen.component;
    assert.ok(overlay, "the command opens the overlay");
    const empty = overlay.render(60).join("\n");
    assert.match(empty, /Timers/);
    assert.match(empty, /No timers have run in this session/);
    assert.match(empty, /Press Escape to close/);

    await start({ id: "timer-a", condition: "false" });
    await start({ id: "longer-timer", intervalSec: 5, maxTicks: 2 });

    const lines = overlay.render(80);
    assert.ok(
      !lines.some((line) => /^\s*ID\s+STATE/.test(line)),
      "the table has no header row",
    );
    assert.ok(
      lines.some((line) => line.trim() === "2 running, 0 finished"),
      "the summary counts the running and the finished timers",
    );
    const rows = lines.filter((line) => line.includes("ticks "));
    // Every row reserves a cursor column, so the ids line up with or without
    // the mark in front of the selected row.
    const rowText = (row) => row.replace(SELECTED_CURSOR, " ").trim();
    // Both still run, so the list reads in the order they were armed.
    assert.deepEqual(
      rows.map((row) => rowText(row).split(/ +/)[0]),
      ["timer-a", "longer-timer"],
    );
    assert.equal(
      lines.filter((line) => line.includes(SELECTED_CURSOR)).length,
      1,
      "the first row starts selected",
    );
    // Every row names its id first, with the spinner right after it, so the
    // markers line up as one column like the /subagents rows.
    for (const row of rows) {
      assert.match(rowText(row), /^\S+ +[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] running /);
    }
    for (const column of ["running", "ticks "]) {
      assert.equal(new Set(rows.map((row) => row.indexOf(column))).size, 1);
    }
    // Rows are highlighted like the subagent overlay: accent marker, bold id,
    // muted state and age, dim tick budget and target.
    assert.ok(bolded.some((text) => text.trim() === "timer-a"));
    assert.ok(colored.some((entry) => entry.color === "accent"));
    assert.ok(
      colored.some(
        (entry) => entry.color === "muted" && entry.text.trim() === "running",
      ),
    );
    assert.ok(
      colored.some(
        (entry) => entry.color === "dim" && entry.text.includes("cond:"),
      ),
    );

    overlay.handleInput("\x1b");
    await showing;
    assert.equal(screen.component, undefined, "Escape closes the overlay");

    const notified = [];
    await command.handler("", {
      mode: "print",
      ui: { notify: (text) => notified.push(text) },
    });
    assert.match(notified[0], /^timer-a +running/m);
  });

  test("/timers fits a short terminal and scrolls the list", async (t) => {
    const { start, commands } = setup(t, runUntilCancelled);
    const rows = 20;
    // The fake UI cannot verify the real reserve, but a page that grows past it
    // would clip.
    const screen = fakeUI(t, { rows });

    const showing = commands
      .get("timers")
      .handler("", { mode: "tui", ui: screen.ui });
    const overlay = screen.component;
    const ids = [
      "tim1",
      "tim2",
      "tim3",
      "tim4",
      "tim5",
      "tim6",
      "tim7",
      "tim8",
    ];
    for (const id of ids) {
      await start({ id, condition: "false", intervalSec: 3600 });
    }

    /** The list as the user sees it, in a terminal this short. */
    const shown = () => {
      const lines = overlay.render(80);
      assert.ok(
        lines.length <= rows - VIEWPORT_RESERVE_ROWS,
        `page leaves pi its rows: ${lines.length} of ${rows}`,
      );
      return lines.join("\n");
    };

    const first = shown();
    assert.match(first, /Timers/);
    assert.match(first, /8 running, 0 finished/);
    assert.match(first, /Escape to close/);
    assert.match(first, /up\/down scroll/);
    assert.doesNotMatch(first, /\btim8\b/);

    // Paging down reaches the timers the window hides, and its hint says so.
    for (let page = 0; page < 3; page += 1) overlay.handleInput("\x1b[6~");
    const later = shown();
    assert.match(later, /\btim8\b/);
    assert.match(later, /Escape to close/);

    overlay.handleInput("\x1b");
    await showing;
    assert.equal(screen.component, undefined, "Escape closes the overlay");
  });

  test("/timers keeps a timer that ended, with its glyph and state word", async (t) => {
    const { start, stop, commands, noticesAfter } = setup(t, (command) =>
      exit(command === "true" ? 0 : 1),
    );
    const screen = fakeUI(t);
    const command = commands.get("timers");

    const showing = command.handler("", { mode: "tui", ui: screen.ui });
    const overlay = screen.component;

    // A condition that holds at once ends the first timer; a user stop ends the
    // second one. Both must still be listed, not dropped from the view.
    await start({ id: "cond-met", condition: "true", maxTicks: 0 });
    await noticesAfter(1);
    const done = pageOf(overlay, 80);
    assert.match(done, /^\s*cond-met +✓ done \d+s +- +condition met\s*$/m);
    assert.match(done, /0 running, 1 finished/);

    await start({ id: "peek-stop", condition: "false", timeoutSec: 600 });
    await stop({ id: "peek-stop" });
    const stopped = pageOf(overlay, 80);
    assert.match(stopped, /^\s*peek-stop +· killed \d+s/m);
    assert.match(stopped, /0 running, 2 finished/);

    // A timer that ran no command has no log: its detail is the specification
    // alone, with nothing to scroll.
    overlay.handleInput("\r");
    const detail = pageOf(overlay, 80);
    assert.match(
      detail,
      new RegExp(
        `cond-met\\s+✓ done after \\d+s budget=${DEFAULT_TIMEOUT_SEC}s running`,
      ),
    );
    assert.match(detail, /cond: true/);
    assert.match(detail, /Escape to go back/);
    assert.doesNotMatch(detail, /up\/down scroll/);
    overlay.handleInput("\x1b");

    overlay.handleInput("\x1b");
    await showing;
    assert.equal(screen.component, undefined, "Escape closes the overlay");
  });

  test("/timers lists running timers above ended ones, each oldest first", async (t) => {
    const { hooks, stop, commands, branch } = setup(t, () => exit(1));

    const now = Date.now();
    await hooks.get("session_tree")(
      {},
      branch(
        armedSpec("armed-first", now - 5_000),
        armedSpec("armed-second", now - 3_000),
        armedSpec("armed-third", now - 1_000),
      ),
    );
    // Ended in the reverse of the order they were armed, so only sorting the
    // ended rows by creation lists armed-first before armed-second, and the
    // running one comes first though it was armed last.
    await stop({ id: "armed-second" });
    await stop({ id: "armed-first" });

    const screen = fakeUI(t);
    const showing = commands
      .get("timers")
      .handler("", { mode: "tui", ui: screen.ui });
    assert.deepEqual(
      listedIds(screen.component, [
        "armed-first",
        "armed-second",
        "armed-third",
      ]),
      ["armed-third", "armed-first", "armed-second"],
    );

    screen.component.handleInput("\x1b");
    await showing;
  });

  test("a row keeps its place when its timer ends while the overlay is open", async (t) => {
    const { hooks, stop, commands, branch } = setup(t, () => exit(1));

    const now = Date.now();
    await hooks.get("session_tree")(
      {},
      branch(
        armedSpec("first", now - 3_000),
        armedSpec("second", now - 2_000),
        armedSpec("third", now - 1_000),
      ),
    );

    const screen = fakeUI(t);
    const command = commands.get("timers");
    const showing = command.handler("", { mode: "tui", ui: screen.ui });
    const overlay = screen.component;
    assert.deepEqual(listedIds(overlay, ["first", "second", "third"]), [
      "first",
      "second",
      "third",
    ]);

    // The timer ends where the reader already is, so its row stays put and only
    // its state changes under it.
    await stop({ id: "second" });
    assert.match(pageOf(overlay), /^\s*second +· killed /m);
    assert.deepEqual(listedIds(overlay, ["first", "second", "third"]), [
      "first",
      "second",
      "third",
    ]);
    assert.match(pageOf(overlay), /2 running, 1 finished/);

    overlay.handleInput("\x1b");
    await showing;

    // Reopening sorts the ended row below the running ones.
    const reopened = command.handler("", { mode: "tui", ui: screen.ui });
    assert.deepEqual(
      listedIds(screen.component, ["first", "second", "third"]),
      ["first", "third", "second"],
    );
    screen.component.handleInput("\x1b");
    await reopened;
  });

  test("/timers marks failed, timed-out and signal-killed timers", async (t) => {
    const { start, hooks, commands, noticesAfter, branch } = setup(
      t,
      (command) => {
        if (command === "snap") throw new Error("boom");
        return exit(1);
      },
    );
    const screen = fakeUI(t);
    const showing = commands
      .get("timers")
      .handler("", { mode: "tui", ui: screen.ui });
    const overlay = screen.component;

    // A condition that throws fails the timer.
    await start({ id: "cond-boom", condition: "snap", maxTicks: 0 });
    await noticesAfter(1);
    assert.match(pageOf(overlay), /^\s*cond-boom +✗ failed /m);

    // A job its own command kills is killed, not failed: the timer did not fail.
    await start({ id: "self-kill", start: "kill -TERM $$" });
    const [, killed] = await noticesAfter(2);
    assert.match(killed.content, /killed by SIGTERM .*not by the timer/);
    assert.equal(killed.details.state, "killed");
    assert.match(pageOf(overlay), /^\s*self-kill +· killed /m);

    // A timer restored from a branch gets a fresh budget; this one runs out a
    // second later. Restoring a branch starts a fresh history, so it stands
    // alone.
    await hooks.get("session_tree")(
      {},
      branch({
        action: "start",
        id: "stale",
        condition: "false",
        intervalSec: 1,
        maxTicks: 0,
        timeoutSec: 1,
        startedAt: Date.now() - 2_000,
      }),
    );
    await noticesAfter(3);
    assert.match(pageOf(overlay), /^\s*stale +⧖ timeout /m);

    overlay.handleInput("\x1b");
    await showing;
  });

  test("/timers opens the selected timer's detail with its log tail", async (t) => {
    const { start, commands } = setup(t, runUntilCancelled);
    const screen = fakeUI(t, { rows: 20 });
    const showing = commands
      .get("timers")
      .handler("", { mode: "tui", ui: screen.ui });
    const overlay = screen.component;

    const { details } = await start({
      id: "live-job",
      start: "printf 'line-%s\\n' $(seq 1 40); sleep 60",
    });
    await until(
      () => readFileSync(details.logPath, "utf8").includes("line-40"),
      "the job writes its whole log",
    );

    assert.match(pageOf(overlay), /live-job/);
    assert.match(pageOf(overlay), /Enter for details, Escape to close/);

    overlay.handleInput("\r");
    // Wide enough for the log path to stay on one line; the specification may
    // still wrap, so read it as one text.
    const detail = pageOf(overlay, 200);
    const lines = linesOf(detail);
    const flat = detail.replace(/\s+/g, " ");
    assert.match(
      detail,
      new RegExp(
        `^\\s*live-job\\s+[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] running for \\d+s deadline=${DEFAULT_TIMEOUT_SEC}s\\s*$`,
        "m",
      ),
    );
    assert.match(flat, /started=\d\d:\d\d:\d\d, pid \d+, /);
    assert.ok(flat.includes(details.logPath), "the detail names the log file");
    assert.ok(
      flat.includes("printf 'line-%s\\n' $(seq 1 40); sleep 60"),
      "the detail names the command it runs",
    );
    // The view opens at the end of the log, following the newest line.
    assert.ok(lines.includes("line-40"), "newest log line");
    assert.ok(!lines.includes("line-1"), "oldest log line is above the window");
    assert.match(detail, /Escape to go back/);

    // Paging up walks back towards the oldest line.
    for (let step = 0; step < 8; step += 1) overlay.handleInput("\x1b[5~");
    assert.ok(linesOf(pageOf(overlay)).includes("line-1"), "oldest log line");

    // Escape walks back to the list; a second one closes the overlay.
    overlay.handleInput("\x1b");
    const back = pageOf(overlay);
    assert.match(back, /Enter for details, Escape to close/);
    assert.doesNotMatch(back, /Escape to go back/);

    overlay.handleInput("\x1b");
    await showing;
    assert.equal(screen.component, undefined, "Escape from the list closes");
  });

  test("/timers fits its detail and log in a short terminal", async (t) => {
    const { start, commands } = setup(t, runUntilCancelled);

    const { details } = await start({
      id: "live-job",
      start: "printf 'line-%s\\n' $(seq 1 40); sleep 60",
    });
    await until(
      () => readFileSync(details.logPath, "utf8").includes("line-40"),
      "the job writes its whole log",
    );

    /**
     * The detail page at one terminal height.
     *
     * @param rows - Terminal height the page renders into.
     * @returns The rendered page and the rows pi leaves for it.
     */
    const detailAt = async (rows) => {
      const screen = fakeUI(t, { rows });
      const showing = commands
        .get("timers")
        .handler("", { mode: "tui", ui: screen.ui });
      screen.component.handleInput("\r");
      const page = screen.component.render(100);
      // Leave through both views so the next height opens a fresh page.
      screen.component.handleInput("\x1b");
      screen.component.handleInput("\x1b");
      await showing;
      assert.equal(screen.component, undefined, "both Escapes close the page");
      return { page, budget: rows - VIEWPORT_RESERVE_ROWS };
    };

    // The page keeps pi's rows and its own hint at every height the box fits in
    // at all. The list has the same 13-row floor, which is the chrome alone.
    for (let rows = 13; rows <= 22; rows += 1) {
      const { page, budget } = await detailAt(rows);
      assert.ok(
        page.length <= budget,
        `the detail leaves pi its rows at ${rows}: ${page.length} of ${budget}`,
      );
      if (rows < 15) continue;
      const shown = page.filter((line) => /line-\d+/.test(line));
      assert.ok(shown.length > 0, `the log keeps a row at ${rows} rows`);
    }

    // At a workable height the specification and several log lines both fit.
    const { page } = await detailAt(20);
    const text = page.join("\n");
    assert.match(text, /started=\d\d:\d\d:\d\d/);
    const logLines = linesOf(text).filter((line) => /line-\d+/.test(line));
    assert.ok(logLines.includes("line-40"), "the newest line");
    assert.ok(logLines.length >= 2, "more than the newest line fits");
  });

  test("/timers keeps a retired job's detail, log and end reason", async (t) => {
    const { start, commands, noticesAfter } = setup(t, runUntilCancelled);
    const screen = fakeUI(t);
    const showing = commands
      .get("timers")
      .handler("", { mode: "tui", ui: screen.ui });
    const overlay = screen.component;

    const { details } = await start({ id: "build", start: "echo built-ok" });
    await noticesAfter(1);

    overlay.handleInput("\r");
    const detail = pageOf(overlay, 200);
    const lines = linesOf(detail);
    // The specification may wrap, so read the page as one text.
    const flat = detail.replace(/\s+/g, " ");
    // The header keeps the state, the age at the end and the deadline; a job
    // timer has no interval or tick budget to report.
    assert.match(
      detail,
      new RegExp(
        `^\\s*build\\s+✓ done after \\d+s deadline=${DEFAULT_TIMEOUT_SEC}s\\s*$`,
        "m",
      ),
    );
    assert.doesNotMatch(detail, /interval=/);
    assert.ok(flat.includes("ended: exited 0"), "end reason");
    assert.ok(flat.includes(details.logPath), "log path");
    assert.ok(flat.includes("echo built-ok"), "command");
    assert.ok(lines.includes("built-ok"), "the log outlives the timer");
    assert.ok(lines.includes("[exit 0]"), "the log records how it ended");

    // Escape walks back to the list, and a second one closes the overlay.
    overlay.handleInput("\x1b");
    assert.match(pageOf(overlay, 200), /Enter for details/);
    overlay.handleInput("\x1b");
    await showing;
    assert.equal(screen.component, undefined, "Escape from the list closes");
  });

  test("a stop during a slow last tick sends no late wake and stays killed", async (t) => {
    let release;
    const captured = new Promise((resolve) => {
      release = resolve;
    });
    let capturing;
    const capturingStarted = new Promise((resolve) => {
      capturing = resolve;
    });
    const { start, stop, status, notices } = setup(t, async (command) => {
      if (command !== "slow-snap") return exit(1);
      capturing();
      await captured;
      return exit(0, "late output");
    });

    await start({
      id: "last-tick",
      onTick: "slow-snap",
      intervalSec: 1,
      maxTicks: 1,
      timeoutSec: 30,
    });
    await capturingStarted;
    await stop({ id: "last-tick" });
    release();
    await wait(50);

    assert.equal(notices.length, 0, "a stopped timer does not wake the agent");
    assert.equal(
      (await status({ id: "last-tick" })).content[0].text,
      'Timer "last-tick" stopped (killed by timer_stop).',
    );
  });

  test("a branch restore during a slow last tick keeps the replacement timer", async (t) => {
    let release;
    const captured = new Promise((resolve) => {
      release = resolve;
    });
    let capturing;
    const capturingStarted = new Promise((resolve) => {
      capturing = resolve;
    });
    let slow = true;
    const { start, hooks, status, branch } = setup(t, async (command) => {
      if (command !== "slow-snap" || !slow) return exit(1);
      slow = false;
      capturing();
      await captured;
      return exit(0);
    });

    const { details } = await start({
      id: "replaced",
      onTick: "slow-snap",
      intervalSec: 1,
      maxTicks: 1,
      timeoutSec: 30,
    });
    await capturingStarted;
    // The replayed start replaces the timer whose loop is mid-capture.
    await hooks.get("session_tree")({}, branch(details));
    release();
    await wait(50);

    assert.match(
      (await status({ id: "replaced" })).content[0].text,
      /^replaced +running /,
      "the old loop must not retire the timer that replaced it",
    );
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

    assert.equal(notice.details.id, "restored-timer");
    assert.match(notice.content, /condition met .*\n\nrestored snapshot$/);
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

  test("a forked session does not inherit the timers of its source", async (t) => {
    const { hooks, status, notices, notified } = setup(t, runUntilCancelled);
    // A fork is marked by the parent session path in its header. Its transcript
    // is the source's, so replaying it would duplicate wakes the source owns.
    const forked = {
      sessionManager: {
        getSessionId: () => randomUUID(),
        getHeader: () => ({ parentSession: "/tmp/source.jsonl" }),
        getBranch: () => [
          {
            type: "message",
            message: {
              role: "toolResult",
              toolName: "timer_start",
              details: armedSpec("inherited", Date.now()),
            },
          },
        ],
      },
    };

    await hooks.get("session_start")({}, forked);

    assert.equal((await status({})).content[0].text, "No active timers.");
    assert.deepEqual(notices, []);
    assert.deepEqual(notified, []);
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
        getSessionId: () => "legacy-session",
        getHeader: () => null,
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
    await until(() => captures > before, "the restored timer never ticked");
    // A duplicate loop shares the phase, so its capture lands at the same moment:
    // a short settle is enough to catch it, well inside the next interval.
    await wait(300);

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

  test("a job that exits 0 wakes with its output and the exit marker", async (t) => {
    const { start, noticesAfter } = setup(t, () => exit(1));

    const result = await start({ id: "job-ok", start: "echo hi" });
    const [notice] = await noticesAfter(1);

    assert.match(
      notice.content,
      /^\[timer job-ok\] exited 0 after \ds; timer stopped\n\nhi\n\[exit 0\]$/,
    );
    assert.equal(notice.details.state, "done");
    assert.equal(result.details.start, "echo hi");
    assert.equal(result.details.maxTicks, 0);
    assert.equal(result.details.timeoutSec, DEFAULT_TIMEOUT_SEC);
    assert.match(
      result.content[0].text,
      new RegExp(
        `^Started job "job-ok": runs \`echo hi\` in the background, no tick wakes, log .*\\/jobs\\/job-ok-\\d+\\.log; wakes you when it exits or after ${DEFAULT_TIMEOUT_SEC}s of real time\\. Its own shell kills it at that deadline, even while pi is closed; it is re-attached when you resume this session, and only \`timer_stop\` or the deadline ends it\\.$`,
      ),
    );
    // The log outlives the wake, so it must record the outcome too.
    assert.equal(
      readFileSync(result.details.logPath, "utf8"),
      "hi\n[exit 0]\n",
    );
  });

  test("a job that exits non-zero wakes with failed: exit 3", async (t) => {
    const { start, noticesAfter } = setup(t, () => exit(1));

    const result = await start({
      id: "job-fail",
      start: "echo nope >&2; exit 3",
    });
    const [notice] = await noticesAfter(1);

    assert.match(
      notice.content,
      /^\[timer job-fail\] failed: exit 3 after \ds; timer stopped\n\nnope\n\[exit 3\]$/,
    );
    assert.equal(
      readFileSync(result.details.logPath, "utf8"),
      "nope\n[exit 3]\n",
    );
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

    const result = await start({
      id: "job-timeout",
      start: "sleep 30",
      timeoutSec: 1,
    });
    const pid = await jobPid(status, "job-timeout");
    const [notice] = await noticesAfter(1);

    assert.match(
      notice.content,
      /^\[timer job-timeout\] timeout after 1s; job killed; timer stopped\n\n\[pi-timer [0-9a-f-]+: timeout after 1s\]$/,
    );
    assert.equal(notice.details.state, "timeout");
    assert.match(
      readFileSync(result.details.logPath, "utf8"),
      /\[pi-timer [0-9a-f-]+: timeout after 1s\]\n$/,
    );
    await waitGone(pid);
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
    assert.match(
      readFileSync(result.details.logPath, "utf8"),
      /\[killed by timer_stop\]\n$/,
    );
    // The exit the kill causes must not wake the agent: it asked for the stop.
    await wait(300);
    assert.deepEqual(notices, []);
  });

  test("a pi process exits without waiting for the job it started", async (t) => {
    // A real second process: without unref'ing the job, node waits for it, and
    // quitting pi would hang for as long as the job runs.
    const sessionId = randomUUID();
    const extension = new URL("../extensions/timer.ts", import.meta.url).href;
    const script = join(agentDir, "start-timer-child.mjs");
    writeFileSync(
      script,
      `import timerExtension from ${JSON.stringify(extension)};
const tools = new Map();
const hooks = new Map();
timerExtension({
  registerTool: (definition) => tools.set(definition.name, definition),
  registerCommand: () => {},
  on: (name, handler) => hooks.set(name, handler),
  exec: async () => ({ code: 1, stdout: "", stderr: "" }),
  sendMessage: () => {},
});
const ctx = {
  sessionManager: {
    getSessionId: () => ${JSON.stringify(sessionId)},
    getHeader: () => null,
    getBranch: () => [],
  },
  ui: { notify: () => {} },
};
await hooks.get("session_start")({}, ctx);
await tools.get("timer_start").execute("test", {
  id: "job-orphan",
  start: "sleep 30",
  timeoutSec: 60,
});
const listed = await tools.get("timer_status").execute("test", {});
await hooks.get("session_shutdown")({});
console.log(listed.content[0].text);
`,
    );

    const child = spawn(process.execPath, [script], {
      stdio: ["ignore", "pipe", "ignore"],
    });
    let output = "";
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      output += chunk;
    });
    const exited = new Promise((resolve) => child.once("exit", resolve));
    const code = await Promise.race([
      exited,
      wait(10_000).then(() => "timeout"),
    ]);
    if (code === "timeout") {
      child.kill();
      assert.fail("the pi process waited for its job instead of exiting");
    }

    assert.equal(code, 0);
    const pid = Number(output.match(/job pid (\d+)/)[1]);
    assert.ok(
      pidAlive(pid),
      "the job is still running after the pi process exited",
    );

    // The next pi process adopts the same job and can still stop it.
    const next = setup(t, () => exit(1), { sessionId });
    await next.hooks.get("session_start")({}, next.branch());
    assert.match(
      (await next.status({ id: "job-orphan" })).content[0].text,
      new RegExp(`^job-orphan +running .*job pid ${pid}, log `),
    );
    await next.stop({ id: "job-orphan" });
    await waitGone(pid);
  });

  test("session shutdown leaves a running job for the next pi process", async (t) => {
    const sessionId = randomUUID();
    const first = setup(t, () => exit(1), { sessionId });
    await first.hooks.get("session_start")({}, first.branch());
    await first.start({ id: "job-pause", start: "sleep 30" });
    const pid = await jobPid(first.status, "job-pause");

    await first.hooks.get("session_shutdown")({});

    // The job is the next process's to re-attach, not this one's to kill.
    assert.ok(pidAlive(pid), "the job outlives the pi process that started it");
    assert.ok(existsSync(stateFileOf(sessionId)), "the timer is checkpointed");

    // A second pi on the same session takes it over without rerunning it.
    const second = setup(t, () => exit(1), { sessionId });
    await second.hooks.get("session_start")({}, second.branch());
    assert.match(
      (await second.status({ id: "job-pause" })).content[0].text,
      new RegExp(`^job-pause +running .*job pid ${pid}, log `),
    );
    assert.match(
      second.notified[0],
      /^Resumed 1 timer from before this pi start\.$/,
    );
    assert.deepEqual(second.notices, [], "a live job is not reported as ended");

    const stopped = await second.stop({ id: "job-pause" });
    assert.match(stopped.content[0].text, /killed its job/);
    await waitGone(pid);
  });

  test("a resumed timer keeps its spent budget, not the wall clock", async (t) => {
    const sessionId = randomUUID();
    // Armed an hour ago, but pi only ever saw two seconds of it.
    writeState(sessionId, [
      persistedTimer("clock", {
        condition: "false",
        timeoutSec: 10,
        activeMs: 2_000,
        startedAt: Date.now() - 3_600_000,
      }),
    ]);
    const { hooks, status, stop, notices, notified, branch } = setup(
      t,
      () => exit(1),
      { sessionId },
    );

    await hooks.get("session_start")({}, branch());

    assert.match(
      (await status({ id: "clock" })).content[0].text,
      /^clock +running +[23]s /,
      "the age is pi-live time, not the hour since it was armed",
    );
    assert.deepEqual(notices, [], "an unexpired timer sends no wake");
    assert.match(notified[0], /^Resumed 1 timer from before this pi start\.$/);
    await stop({ id: "clock" });
  });

  test("a reload re-attaches timers without telling the user", async (t) => {
    const sessionId = randomUUID();
    writeState(sessionId, [persistedTimer("reloaded", { condition: "false" })]);
    const { hooks, status, notified, branch } = setup(t, () => exit(1), {
      sessionId,
    });

    await hooks.get("session_start")({ reason: "reload" }, branch());

    assert.match(
      (await status({ id: "reloaded" })).content[0].text,
      /^reloaded +running /,
      "the timer is re-attached on a reload",
    );
    assert.deepEqual(notified, [], "a reload is not news for the user");
  });

  test("a timer whose budget ran out before shutdown times out on resume", async (t) => {
    const sessionId = randomUUID();
    writeState(sessionId, [
      persistedTimer("spent", {
        condition: "false",
        timeoutSec: 2,
        activeMs: 2_000,
      }),
    ]);
    const { hooks, noticesAfter, status, branch } = setup(t, () => exit(1), {
      sessionId,
    });

    await hooks.get("session_start")({}, branch());
    const wake = (await noticesAfter(1)).at(-1);

    assert.match(
      wake.content,
      /^\[timer spent\] timeout after 2s; timer stopped$/,
    );
    assert.equal(wake.details.state, "timeout");
    assert.equal(
      (await status({ id: "spent" })).content[0].text,
      'Timer "spent" stopped (timed out).',
    );
  });

  test("a resumed timer keeps its tick count and remaining budget", async (t) => {
    const sessionId = randomUUID();
    writeState(sessionId, [
      persistedTimer("ticks", {
        intervalSec: 1,
        maxTicks: 2,
        timeoutSec: 30,
        activeMs: 5_000,
        ticksSent: 1,
      }),
    ]);
    const { hooks, noticesAfter, branch } = setup(t, () => exit(1), {
      sessionId,
    });

    await hooks.get("session_start")({}, branch());
    const wake = (await noticesAfter(1)).at(-1);

    assert.match(
      wake.content,
      /^\[timer ticks\] tick 2\/2, [56]s elapsed; timer stopped$/,
    );
  });

  test("a job that ended while pi was away reports its recorded exit", async (t) => {
    const sessionId = randomUUID();
    const logPath = join(agentDir, "jobs", "away.log");
    mkdirSync(join(agentDir, "jobs"), { recursive: true });
    writeFileSync(logPath, "built ok\n[exit 3]\n");
    writeState(sessionId, [
      persistedTimer("away", {
        start: "make build",
        logPath,
        maxTicks: 0,
        activeMs: 1_000,
        job: {
          pid: DEAD_PID,
          logPath,
          startedAt: Date.now() - 5_000,
          tag: "gone-tag",
        },
      }),
    ]);
    const { hooks, noticesAfter, status, branch } = setup(t, () => exit(1), {
      sessionId,
    });

    await hooks.get("session_start")({}, branch());
    const wake = (await noticesAfter(1)).at(-1);

    assert.match(
      wake.content,
      /^\[timer away\] failed: exit 3 after 5s; timer stopped\n\nbuilt ok\n\[exit 3\]$/,
    );
    assert.equal(wake.details.id, "away");
    assert.equal(
      (await status({ id: "away" })).content[0].text,
      'Timer "away" stopped (failed: exit 3).',
    );
  });

  test("a job that vanished while pi was away reports a lost exit status", async (t) => {
    const sessionId = randomUUID();
    const logPath = join(agentDir, "jobs", "lost.log");
    mkdirSync(join(agentDir, "jobs"), { recursive: true });
    writeFileSync(logPath, "still working\n");
    writeState(sessionId, [
      persistedTimer("lost", {
        start: "make build",
        logPath,
        maxTicks: 0,
        job: {
          pid: DEAD_PID,
          logPath,
          startedAt: Date.now() - 3_000,
          tag: "gone-tag",
        },
      }),
    ]);
    const { hooks, noticesAfter, branch } = setup(t, () => exit(1), {
      sessionId,
    });

    await hooks.get("session_start")({}, branch());
    const wake = (await noticesAfter(1)).at(-1);

    assert.match(
      wake.content,
      /^\[timer lost\] the job ended while pi was not running, after 3s; timer stopped\n\nstill working$/,
    );
    assert.equal(wake.details.state, "failed");
  });

  test("an adopted job's own shell ends it at its deadline", async (t) => {
    const sessionId = randomUUID();
    const tag = randomUUID();
    const { pid, logPath } = spawnJobShell("sleep 30", tag, 1);
    killGroupAfter(t, pid);
    writeState(sessionId, [
      persistedTimer("adopted", {
        start: "sleep 30",
        logPath,
        maxTicks: 0,
        timeoutSec: 1,
        job: { pid, logPath, startedAt: Date.now(), tag },
      }),
    ]);
    const { hooks, noticesAfter, branch } = setup(t, () => exit(1), {
      sessionId,
    });

    await hooks.get("session_start")({}, branch());
    const wake = (await noticesAfter(1)).at(-1);

    assert.match(
      wake.content,
      /^\[timer adopted\] timeout after 1s; job killed; timer stopped\n\n\[pi-timer [0-9a-f-]+: timeout after 1s\]$/,
    );
    assert.equal(wake.details.state, "timeout");
    await waitGone(pid);
    assert.match(
      readFileSync(logPath, "utf8"),
      /\[pi-timer [0-9a-f-]+: timeout after 1s\]\n$/,
    );
  });

  test("a job's own shell enforces its deadline while pi is not running", async (t) => {
    const sessionId = randomUUID();
    const first = setup(t, () => exit(1), { sessionId });
    await first.hooks.get("session_start")({}, first.branch());
    const { details } = await first.start({
      id: "job-alone",
      start: "sleep 30",
      timeoutSec: 1,
    });
    const pid = await jobPid(first.status, "job-alone");
    killGroupAfter(t, pid);

    // Nothing is watching: the wrapper's watchdog is the only thing left.
    await first.hooks.get("session_shutdown")({});
    await waitGone(pid);
    assert.match(
      readFileSync(details.logPath, "utf8"),
      /\[pi-timer [0-9a-f-]+: timeout after 1s\]\n$/,
    );

    // The next pi reports the deadline kill from the log, not a lost job.
    const next = setup(t, () => exit(1), { sessionId });
    await next.hooks.get("session_start")({}, next.branch());
    const wake = (await next.noticesAfter(1)).at(-1);

    assert.match(
      wake.content,
      /^\[timer job-alone\] timeout after 1s; job killed; timer stopped\n\n\[pi-timer [0-9a-f-]+: timeout after 1s\]$/,
    );
    assert.equal(
      (await next.status({ id: "job-alone" })).content[0].text,
      'Timer "job-alone" stopped (timed out).',
    );
  });

  test("a resumed job past its deadline is killed by the backstop", async (t) => {
    const sessionId = randomUUID();
    const tag = randomUUID();
    // A shell from a pi that predates the wrapper-owned deadline: no watchdog,
    // so only the registry's backstop can end it.
    const { pid, logPath } = spawnLegacyJobShell("sleep 30", tag);
    killGroupAfter(t, pid);
    writeState(sessionId, [
      persistedTimer("backstop", {
        start: "sleep 30",
        logPath,
        maxTicks: 0,
        timeoutSec: 1,
        job: { pid, logPath, startedAt: Date.now() - 60_000, tag },
      }),
    ]);
    const { hooks, noticesAfter, branch } = setup(t, () => exit(1), {
      sessionId,
    });

    await hooks.get("session_start")({}, branch());
    const wake = (await noticesAfter(1)).at(-1);

    assert.match(
      wake.content,
      /^\[timer backstop\] timeout after 1s; job killed; timer stopped\n\n\[killed by the timer\]$/,
    );
    await waitGone(pid);
    assert.match(readFileSync(logPath, "utf8"), /\[killed by the timer\]\n$/);
  });

  test("a job that ignores TERM is still killed at its deadline", async (t) => {
    const { start, status, noticesAfter } = setup(t, () => exit(1));

    const { details } = await start({
      id: "job-stubborn",
      start: "trap '' TERM; sleep 30",
      timeoutSec: 1,
    });
    const pid = await jobPid(status, "job-stubborn");
    killGroupAfter(t, pid);

    // The wrapper dies on its own group TERM, so the report comes at the
    // deadline; only the escalation after the grace takes the job down.
    const wake = (await noticesAfter(1)).at(-1);
    assert.match(
      wake.content,
      /^\[timer job-stubborn\] timeout after 1s; job killed; timer stopped\n\n\[pi-timer [0-9a-f-]+: timeout after 1s\]$/,
    );
    await waitGone(pid);
    await waitGroupGone(pid);
    assert.match(
      readFileSync(details.logPath, "utf8"),
      /\[pi-timer [0-9a-f-]+: timeout after 1s\]\n$/,
    );
  });

  test("a job's own output cannot pass for a deadline marker", async (t) => {
    const { start, noticesAfter } = setup(t, () => exit(1));

    await start({
      id: "fake-marker",
      start:
        "echo '[exit 124]'; echo '[pi-timer fake-tag: timeout after 1s]'; exit 3",
      timeoutSec: 30,
    });
    const wake = (await noticesAfter(1)).at(-1);

    // The marker must carry the job's real tag, so this is an ordinary exit 3.
    assert.match(
      wake.content,
      /^\[timer fake-marker\] failed: exit 3 after \ds; timer stopped\n\n\[exit 124\]\n\[pi-timer fake-tag: timeout after 1s\]\n\[exit 3\]$/,
    );
    assert.equal(wake.details.state, "failed");
  });

  test("an adopted job that exits on its own reports its exit code", async (t) => {
    const sessionId = randomUUID();
    const tag = randomUUID();
    const { pid, logPath } = spawnJobShell("sleep 0.5; exit 4", tag);
    killGroupAfter(t, pid);
    writeState(sessionId, [
      persistedTimer("adopted-exit", {
        start: "sleep 0.5; exit 4",
        logPath,
        maxTicks: 0,
        timeoutSec: 60,
        job: { pid, logPath, startedAt: Date.now(), tag },
      }),
    ]);
    const { hooks, noticesAfter, branch } = setup(t, () => exit(1), {
      sessionId,
    });

    await hooks.get("session_start")({}, branch());
    const wake = (await noticesAfter(1)).at(-1);

    // Found by the adoption poll, then read from the log the shell wrote.
    assert.match(
      wake.content,
      /^\[timer adopted-exit\] failed: exit 4 after \ds; timer stopped\n\n\[exit 4\]$/,
    );
    assert.equal(wake.details.state, "failed");
  });

  test("an adopted job that exits before its deadline reports its exit", async (t) => {
    const sessionId = randomUUID();
    const tag = randomUUID();
    // It exits before its 1s deadline; the wrapper must stop its watchdog then,
    // or the deadline would turn a clean exit into a timeout.
    const { pid, logPath } = spawnJobShell("sleep 0.2; exit 0", tag, 1);
    killGroupAfter(t, pid);
    writeState(sessionId, [
      persistedTimer("adopted-race", {
        start: "sleep 0.2; exit 0",
        logPath,
        maxTicks: 0,
        timeoutSec: 1,
        job: { pid, logPath, startedAt: Date.now(), tag },
      }),
    ]);
    const { hooks, noticesAfter, branch } = setup(t, () => exit(1), {
      sessionId,
    });

    await hooks.get("session_start")({}, branch());
    const wake = (await noticesAfter(1)).at(-1);

    assert.match(
      wake.content,
      /^\[timer adopted-race\] exited 0 after \ds; timer stopped\n\n\[exit 0\]$/,
    );
    assert.doesNotMatch(wake.content, /timeout/);
    await waitGone(pid);
  });

  test("a pid that no longer carries its timer's tag is not signalled", async (t) => {
    const sessionId = randomUUID();
    const tag = randomUUID();
    const { pid, logPath } = spawnJobShell("sleep 30", tag);
    killGroupAfter(t, pid);
    // The state file names the live pid but a tag that is not its own, which is
    // what a reboot that reused the pid looks like.
    writeState(sessionId, [
      persistedTimer("reused", {
        start: "sleep 30",
        logPath,
        maxTicks: 0,
        job: { pid, logPath, startedAt: Date.now(), tag: randomUUID() },
      }),
    ]);
    const { hooks, noticesAfter, branch } = setup(t, () => exit(1), {
      sessionId,
    });

    await hooks.get("session_start")({}, branch());
    const wake = (await noticesAfter(1)).at(-1);

    assert.match(
      wake.content,
      /^\[timer reused\] the job ended while pi was not running, after \ds; timer stopped$/,
    );
    assert.equal(wake.details.state, "failed");
    assert.ok(pidAlive(pid), "a pid the timer cannot identify is left alone");
  });

  test("a branch restore kills a job its new branch no longer has", async (t) => {
    const { hooks, start, status, branch } = setup(t, () => exit(1));

    await start({ id: "abandoned", start: "sleep 30" });
    const pid = await jobPid(status, "abandoned");
    killGroupAfter(t, pid);

    // The new branch never saw this timer, so nothing is left to watch its job.
    await hooks.get("session_tree")({}, branch());

    await waitGone(pid);
    assert.equal(
      (await status({})).content[0].text,
      "No active timers.",
      "the abandoned timer is gone with its job",
    );
  });

  test("the state file disappears when no timer is left", async (t) => {
    const sessionId = randomUUID();
    const { hooks, start, stop, branch } = setup(t, runUntilCancelled, {
      sessionId,
    });
    await hooks.get("session_start")({}, branch());

    await start({ id: "file-timer", condition: "false" });
    assert.ok(existsSync(stateFileOf(sessionId)), "arming writes the file");

    await stop({ id: "file-timer" });
    assert.equal(existsSync(stateFileOf(sessionId)), false);
  });

  test("a branch restore keeps the budget a timer already spent", async (t) => {
    const { hooks, start, status, branch } = setup(t, runUntilCancelled);
    const { details } = await start({
      id: "carried",
      condition: "false",
      timeoutSec: 60,
    });
    await wait(1_200);

    await hooks.get("session_tree")({}, branch(details));

    assert.match(
      (await status({ id: "carried" })).content[0].text,
      /^carried +running +[12]s /,
    );
  });

  test(`the exit wake carries only the last ${JOB_TAIL_LINES} log lines`, async (t) => {
    const { start, noticesAfter } = setup(t, () => exit(1));

    const total = JOB_TAIL_LINES * 3;
    await start({ id: "job-tail", start: `seq 1 ${total}` });
    const [notice] = await noticesAfter(1);

    // The marker counts as a line, so the tail keeps the newest lines and drops
    // the oldest.
    const keptLogLines = JOB_TAIL_LINES - 1;
    const firstKept = total - keptLogLines + 1;
    assert.match(
      notice.content,
      new RegExp(`\\n${firstKept}\\n[\\s\\S]*\\n\\[exit 0\\]$`),
    );
    assert.doesNotMatch(notice.content, new RegExp(`^${firstKept - 1}$`, "m"));
    assert.equal(notice.content.split("\n").length, JOB_TAIL_LINES + 2);
  });

  test("onTick output follows the log tail in the exit wake", async (t) => {
    const { start, noticesAfter } = setup(t, (command) =>
      command === "snap" ? exit(0, "snapshot") : exit(1),
    );

    await start({ id: "job-ontick", start: "echo hi", onTick: "snap" });
    const [notice] = await noticesAfter(1);

    assert.match(
      notice.content,
      /^\[timer job-ontick\] exited 0 after \ds; timer stopped\n\nhi\n\[exit 0\]\nsnapshot$/,
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
    const { hooks, start, notices, noticesAfter, branch } = setup(t, () =>
      exit(1),
    );
    const { details } = await start({
      id: "job-reattach",
      start: `echo run >> '${runsPath}'; sleep 0.5`,
    });

    await hooks.get("session_tree")({}, branch(details));
    const [notice] = await noticesAfter(1);

    assert.match(
      notice.content,
      /^\[timer job-reattach\] exited 0 after \ds; timer stopped\n\n\[exit 0\]$/,
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

  test("a job accepts maxTicks 0 and rejects a duplicate id", async (t) => {
    const { start, stop, noticesAfter } = setup(t, () => exit(1));

    const result = await start({
      id: "job-zero",
      start: "echo hi",
      maxTicks: 0,
    });
    assert.equal(result.details.maxTicks, 0);
    assert.match(result.content[0].text, /no tick wakes/);
    await noticesAfter(1);

    await start({ id: "job-dup", start: "sleep 30" });
    await assert.rejects(
      start({ id: "job-dup", start: "echo hi" }),
      /already active: its job is still running, log .*\/jobs\/job-dup-\d+\.log/,
    );
    await stop({ id: "job-dup" });
  });

  test("a job with a tick budget still wakes on exit", async (t) => {
    const { start, notices, noticesAfter } = setup(t, () => exit(1));

    await start({
      id: "job-tick",
      start: "sleep 2.5",
      intervalSec: 1,
      maxTicks: 1,
      timeoutSec: 10,
    });
    await noticesAfter(2);
    await wait(100);

    assert.equal(notices.length, 2);
    assert.equal(notices[0].details.state, "tick");
    assert.match(
      notices[0].content,
      /^\[timer job-tick\] tick 1\/1, \ds elapsed$/,
    );
    assert.equal(notices[1].details.state, "done");
    assert.match(
      notices[1].content,
      /^\[timer job-tick\] exited 0 after \ds; timer stopped/,
    );
  });

  test("start, condition and onTick combine in one timer", async (t) => {
    const conditionInputs = [];
    const tickInputs = [];
    const { start, noticesAfter } = setup(t, (command, _signal, stdin) => {
      if (command === "grep -q never") {
        conditionInputs.push(stdin);
        return exit(1);
      }
      if (command === "report") {
        tickInputs.push(stdin);
        return exit(0, `log:${stdin.trim()}`);
      }
      return exit(1);
    });

    await start({
      id: "job-combo",
      start: "echo job-output; sleep 2.5",
      condition: "grep -q never",
      onTick: "report",
      intervalSec: 1,
      maxTicks: 1,
      timeoutSec: 10,
    });
    const [tick, done] = await noticesAfter(2);

    assert.match(
      tick.content,
      /^\[timer job-combo\] tick 1\/1, \ds elapsed\n\nlog:job-output$/,
    );
    assert.match(
      done.content,
      /^\[timer job-combo\] exited 0 after \ds; timer stopped/,
    );
    // Both callbacks see the job's output while it runs, not only at exit.
    assert.ok(
      conditionInputs.some((text) => text.includes("job-output")),
      "condition never read the job output",
    );
    assert.equal(tickInputs[0], "job-output\n");
  });

  test("a condition on a job is checked immediately, before output", async (t) => {
    let conditionInput;
    const { start, status, noticesAfter } = setup(
      t,
      (_command, _signal, stdin) => {
        conditionInput = stdin;
        return exit(0);
      },
    );

    const { details } = await start({
      id: "job-immediate",
      start: "sleep 30",
      condition: "true",
      intervalSec: 1,
      timeoutSec: 5,
    });
    const [notice] = await noticesAfter(1);

    // The predicate does not depend on the job's output, so it must not wait a
    // tick just because `start` is present.
    assert.equal(conditionInput, "");
    assert.match(
      notice.content,
      /^\[timer job-immediate\] condition met after \ds: true; timer stopped/,
    );
    assert.equal(notice.details.state, "done");
    assert.equal(
      (await status({ id: "job-immediate" })).content[0].text,
      'Timer "job-immediate" stopped (condition met).',
    );
    assert.match(
      readFileSync(details.logPath, "utf8"),
      /\[killed after condition met\]\n$/,
    );
  });

  test("a job exit during a condition keeps the exit status", async (t) => {
    const { start, noticesAfter } = setup(t, (command) => {
      if (command !== "wait-for-exit") return exit(1);
      return new Promise((resolve) => {
        setTimeout(() => resolve(exit(0)), 700);
      });
    });

    await start({
      id: "job-race",
      start: "sleep 0.5; exit 3",
      condition: "wait-for-exit",
      intervalSec: 1,
      timeoutSec: 5,
    });
    const [notice] = await noticesAfter(1);

    assert.match(
      notice.content,
      /^\[timer job-race\] failed: exit 3 after \ds; timer stopped/,
    );
    assert.equal(notice.details.state, "failed");
    assert.doesNotMatch(notice.content, /killed after condition met/);
  });

  test("a condition that holds on a running job kills it", async (t) => {
    const { start, status, noticesAfter } = setup(
      t,
      (command, _signal, stdin) => {
        if (command !== "grep -q ready") return exit(1);
        return stdin.includes("ready") ? exit(0) : exit(1);
      },
    );

    const { details } = await start({
      id: "job-cond",
      start: "sleep 0.5; echo ready; sleep 30",
      condition: "grep -q ready",
      intervalSec: 1,
      timeoutSec: 10,
    });
    const pid = await jobPid(status, "job-cond");
    const [notice] = await noticesAfter(1);

    assert.match(
      notice.content,
      /^\[timer job-cond\] condition met after \ds: grep -q ready; timer stopped\n\nready\n\[killed after condition met\]$/,
    );
    assert.equal(notice.details.state, "done");
    assert.equal(
      (await status({ id: "job-cond" })).content[0].text,
      'Timer "job-cond" stopped (condition met).',
    );
    const log = readFileSync(details.logPath, "utf8");
    assert.match(log, /ready\n\[killed after condition met\]\n$/);
    assert.equal(log.match(/\[killed after condition met\]/g).length, 1);
    await waitGone(pid);
  });

  test("a log deleted before exit gives onTick empty stdin, not an error", async (t) => {
    const { start, noticesAfter } = setup(t, (command) =>
      command === "report" ? exit(0, "snapshot") : exit(1),
    );

    const { details } = await start({
      id: "job-lost-log",
      start: "sleep 0.3",
      onTick: "report",
    });
    rmSync(details.logPath);
    const [notice] = await noticesAfter(1);

    assert.match(notice.content, /\nsnapshot$/);
    assert.doesNotMatch(notice.content, /No such file or directory/);
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

  test("status reports a running job's pid and log path", async (t) => {
    const { start, status, stop } = setup(t, () => exit(1));
    await start({ id: "job-h", start: "sleep 30" });

    const listed = (await status({ id: "job-h" })).content[0].text;
    assert.match(
      listed,
      /^job-h {2}running {2}\d+s {2}ticks 0\/0 {2}job pid \d+, log .*\/jobs\/job-h-\d+\.log$/,
    );
    await stop({ id: "job-h" });
  });
});
