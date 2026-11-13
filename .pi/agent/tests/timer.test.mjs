import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";

import timerExtension, { SELECTED_CURSOR } from "../extensions/timer.ts";

const { KeybindingsManager, TUI_KEYBINDINGS } = await import(
  "@earendil-works/pi-tui"
);

// Job logs go under the agent dir; keep them out of the real one.
const agentDir = mkdtempSync(join(tmpdir(), "pi-timer-tests-"));
process.env.PI_CODING_AGENT_DIR = agentDir;
after(() => rmSync(agentDir, { recursive: true, force: true }));

/** A command result, in the shape `pi.exec()` returns. */
const exit = (code, stdout = "") => ({ code, stdout, stderr: "" });

/**
 * Load the extension with a fake `pi`.
 *
 * @param t - Test context, used to shut the session down afterwards.
 * @param runCommand - Fake shell for `condition` and `onTick`; `start` jobs
 *   spawn a real bash instead.
 * @param options - `ack: false` leaves wakes unread, to test coalescing.
 * @returns Handles for the registered tools, hooks, and captured notices.
 */
function setup(t, runCommand, { ack = true } = {}) {
  const tools = new Map();
  const hooks = new Map();
  const commands = new Map();
  const notices = [];
  let onNotice = () => {};
  timerExtension({
    registerTool: (definition) => {
      tools.set(definition.name, definition);
    },
    registerCommand: (name, definition) => {
      commands.set(name, definition);
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
  return {
    hooks,
    tools,
    commands,
    start,
    stop,
    status,
    notices,
    noticesAfter,
    branch,
  };
}

/** A fake shell whose commands keep running until the timer cancels them. */
function runUntilCancelled(_command, signal) {
  return new Promise((resolve) =>
    signal.addEventListener("abort", () => resolve(exit(null))),
  );
}

/** Theme that adds no attributes, so tests read the page as plain text. */
const flatTheme = { fg: (_color, text) => text, bold: (text) => text };

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

  test("start rejects a missing id, a bad id, a nameless timer, and two modes", async (t) => {
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
    await assert.rejects(
      start({ id: "both-modes", start: "true", condition: "false" }),
      /start and condition are mutually exclusive/,
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
    assert.deepEqual(
      rows.map((row) => rowText(row).split(/ +/)[0]),
      ["longer-timer", "timer-a"],
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
    // Rows pi keeps around the page are assumed to be 4; the fake UI cannot
    // verify the real reserve, but a page that grows past it would clip.
    const piRows = 4;
    const screen = fakeUI(t, { rows });

    const showing = commands
      .get("timers")
      .handler("", { mode: "tui", ui: screen.ui });
    const overlay = screen.component;
    const ids = ["tim1", "tim2", "tim3", "tim4", "tim5", "tim6", "tim7", "tim8"];
    for (const id of ids) {
      await start({ id, condition: "false", intervalSec: 3600 });
    }

    /** The list as the user sees it, in a terminal this short. */
    const shown = () => {
      const lines = overlay.render(80);
      assert.ok(
        lines.length <= rows - piRows,
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
    assert.match(detail, /cond-met\s+✓ done after \d+s timeout=3600s/);
    assert.match(detail, /cond: true/);
    assert.match(detail, /Escape to go back/);
    assert.doesNotMatch(detail, /up\/down scroll/);
    overlay.handleInput("\x1b");

    overlay.handleInput("\x1b");
    await showing;
    assert.equal(screen.component, undefined, "Escape closes the overlay");
  });

  test("/timers marks failed, timed-out and signal-killed timers", async (t) => {
    const { start, hooks, commands, noticesAfter, branch } = setup(t, (command) => {
      if (command === "snap") throw new Error("boom");
      return exit(1);
    });
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

    // A deadline that passed while the session was closed times the timer out.
    // Restoring a branch starts a fresh history, so this row stands alone.
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
      /^\s*live-job\s+[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] running for \d+s timeout=86400s\s*$/m,
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
      return { page, budget: rows - 4 };
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
    assert.match(detail, /^\s*build\s+✓ done after \d+s timeout=86400s\s*$/m);
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
    assert.equal(result.details.timeoutSec, 86_400);
    assert.match(
      result.content[0].text,
      /^Started job "job-ok": runs `echo hi` in the background, no tick wakes, log .*\/jobs\/job-ok-\d+\.log; wakes you when it exits or after 86400s\. It is killed when this session ends\.$/,
    );
    // The log outlives the wake, so it must record the outcome too.
    assert.equal(readFileSync(result.details.logPath, "utf8"), "hi\n[exit 0]\n");
  });

  test("a job that exits non-zero wakes with failed: exit 3", async (t) => {
    const { start, noticesAfter } = setup(t, () => exit(1));

    const result = await start({ id: "job-fail", start: "echo nope >&2; exit 3" });
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

    const result = await start({ id: "job-timeout", start: "sleep 30", timeoutSec: 1 });
    const pid = await jobPid(status, "job-timeout");
    const [notice] = await noticesAfter(1);

    assert.equal(
      notice.content,
      "[timer job-timeout] timeout after 1s; job killed; timer stopped\n\n[killed by the timer]",
    );
    assert.equal(notice.details.state, "timeout");
    assert.match(
      readFileSync(result.details.logPath, "utf8"),
      /\[killed by the timer\]\n$/,
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

  test("session shutdown kills a running job", async (t) => {
    const { hooks, start, status } = setup(t, () => exit(1));

    await start({ id: "job-shutdown", start: "sleep 30" });
    const pid = await jobPid(status, "job-shutdown");

    await hooks.get("session_shutdown")({});

    await waitGone(pid);
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
    assert.equal(notice.content.split("\n").length, 12);
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
    const { hooks, start, notices, noticesAfter, branch } = setup(t, () => exit(1));
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

    const result = await start({ id: "job-zero", start: "echo hi", maxTicks: 0 });
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
