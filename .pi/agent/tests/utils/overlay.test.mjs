import assert from "node:assert/strict";
import test, { describe } from "node:test";

import { visibleWidth } from "@earendil-works/pi-tui";

import {
  DrillDown,
  listRow,
  OverlayPage,
  padLeft,
  padRight,
  SELECTED_CURSOR,
} from "../../extensions/utils/overlay.ts";

import { VIEWPORT_RESERVE_ROWS } from "../../extensions/utils/page.ts";

const plainTheme = {
  fg: (_color, text) => text,
  bold: (text) => text,
  bg: (_color, text) => text,
};
const STYLED = /\x1b\[[0-9;]*m/g;

/** A TUI the page can measure against, without a real terminal. */
function fakeTui(rows) {
  return { terminal: { rows }, requestRender() {} };
}

/** The page as the user reads it, without styling codes. */
function textOf(lines) {
  return lines.map((line) => line.replace(STYLED, "")).join("\n");
}

/** Input for each pi list action, as the default keybindings map them. */
const KEYS = {
  "tui.select.up": "\x1b[A",
  "tui.select.down": "\x1b[B",
  "tui.select.pageUp": "\x1b[5~",
  "tui.select.pageDown": "\x1b[6~",
  "tui.select.confirm": "\r",
  "tui.select.cancel": "\x1b",
};

const keybindings = {
  matches: (data, action) => KEYS[action] === data,
};

/** Rows a list of the given size shows at the given window size. */
function rowsNamed(count) {
  return Array.from({ length: count }, (_, index) => `row-${index}`);
}

describe("overlay", () => {
  describe("OverlayPage", () => {
    test("draws the title, summary, body and hint inside the terminal's rows", () => {
      const rows = 20;
      const page = new OverlayPage(fakeTui(rows), plainTheme, "Timers");
      page.setSummary("2 running, 1 finished");
      const capacity = page.measure(40, "Enter for details, Escape to close");
      assert.equal(capacity, page.rowCapacity, "measure reports the body rows");
      page.setWindow(
        ["timer-a running", "timer-b running"],
        0,
        capacity,
        "Enter for details, Escape to close",
        40,
      );

      const lines = page.render(40);
      const text = textOf(lines);
      // Pi's own rows stay out of a taller page, or it loses its last rows to
      // the viewport.
      assert.ok(
        lines.length <= rows - VIEWPORT_RESERVE_ROWS,
        `${lines.length} of ${rows} rows`,
      );
      assert.match(text, /Timers/);
      assert.match(text, /2 running, 1 finished/);
      assert.match(text, /timer-a running/);
      assert.match(text, /timer-b running/);
      assert.match(text, /Enter for details, Escape to close/);
      for (const line of lines) {
        assert.equal(visibleWidth(line.replace(STYLED, "")), 40);
      }
    });

    test("pins its head rows above a scrolling body", () => {
      const page = new OverlayPage(fakeTui(30), plainTheme, "Subagents");
      page.setSummary("chatty running for 3s timeout=600s");
      page.setHead(["16:51:36 start"]);
      const capacity = page.measure(100, "Escape to go back");
      page.setWindow(rowsNamed(20), 15, capacity, "Escape to go back", 100);

      const text = textOf(page.render(100));
      assert.match(text, /16:51:36 start/, "the head stays on screen");
      assert.match(text, /row-15/);
      assert.doesNotMatch(text, /row-0\b/, "the body window moved on");
      assert.match(text, /\(16-20 of 20\)/);
    });

    test("reserves no rows for an empty head", () => {
      const page = new OverlayPage(fakeTui(30), plainTheme, "Timers");
      page.setSummary("2 running");
      const bare = page.measure(100, "Escape to go back");

      page.setHead(["started=16:51:36, pid 42"]);
      const pinned = page.measure(100, "Escape to go back");
      assert.equal(pinned, bare - 1, "one head row is one body row fewer");

      page.setHead([]);
      assert.equal(page.measure(100, "Escape to go back"), bare);
    });

    test("shows the window's rows and names the range they sit in", () => {
      const page = new OverlayPage(fakeTui(30), plainTheme, "Todos");
      page.setSummary("5 items");
      page.setWindow(rowsNamed(6), 2, 2, "Press Escape to close", 100);

      const text = textOf(page.render(100));
      assert.match(text, /row-2/);
      assert.match(text, /row-3/);
      assert.doesNotMatch(text, /row-1\b/);
      assert.doesNotMatch(text, /row-4\b/);
      assert.match(
        text,
        /Press Escape to close, up\/down scroll {2}\(3-4 of 6\)/,
      );
    });

    test("drops the scroll hint and range while every row fits", () => {
      const page = new OverlayPage(fakeTui(30), plainTheme, "Todos");
      page.setWindow(rowsNamed(3), 0, 3, "Press Escape to close", 100);

      const lines = textOf(page.render(100)).split("\n");
      const hint = lines.find((line) => line.includes("Press Escape"));
      assert.equal(hint.trim(), "Press Escape to close");
      assert.doesNotMatch(textOf(page.render(100)), /up\/down scroll/);
    });

    test("keeps the hint on one line when the terminal leaves no body row", () => {
      const page = new OverlayPage(fakeTui(5), plainTheme, "Timers");
      const capacity = page.measure(100, "Enter for details, Escape to close");
      assert.equal(capacity, 0);
      page.setWindow(rowsNamed(4), 0, capacity, "Enter for details", 100);

      const text = textOf(page.render(100));
      assert.match(text, /\(4 hidden\)/);
    });

    test("keeps the rows on screen after a resize", () => {
      const page = new OverlayPage(fakeTui(20), plainTheme, "Todos");
      const wide = page.measure(100, "Press Escape to close");
      page.setWindow(rowsNamed(30), 0, wide, "Press Escape to close", 100);
      assert.equal(page.render(100).length, 20 - VIEWPORT_RESERVE_ROWS);

      const narrow = page.measure(20, "Press Escape to close");
      page.setWindow(rowsNamed(30), 0, narrow, "Press Escape to close", 20);
      assert.equal(page.render(20).length, 20 - VIEWPORT_RESERVE_ROWS);
    });
  });

  describe("DrillDown", () => {
    test("moves the list, opens a detail, and Escape walks back out", () => {
      const nav = new DrillDown(() => {});
      const rows = ["one", "two", "three"];
      const state = () => nav.sync(rows, (row) => row);

      assert.equal(state().selected, 0);
      nav.handleInput(KEYS["tui.select.down"], keybindings, rows, 10);
      nav.handleInput(KEYS["tui.select.down"], keybindings, rows, 10);
      nav.handleInput(KEYS["tui.select.down"], keybindings, rows, 10);
      assert.equal(state().selected, 2, "the selection stops at the last row");

      nav.handleInput(KEYS["tui.select.confirm"], keybindings, rows, 10);
      assert.equal(state().detail, "three");
      assert.equal(
        nav.handleInput(KEYS["tui.select.cancel"], keybindings, rows, 10),
        false,
        "Escape with a detail open only closes the detail",
      );
      assert.equal(state().detail, undefined);
      assert.equal(
        nav.handleInput(KEYS["tui.select.cancel"], keybindings, rows, 10),
        true,
        "Escape on the list asks for the page to close",
      );
    });

    test("moves the list by whole pages", () => {
      const nav = new DrillDown(() => {});
      const rows = rowsNamed(10);
      const state = () => nav.sync(rows, (row) => row);

      nav.handleInput(KEYS["tui.select.pageDown"], keybindings, rows, 3);
      assert.equal(state().selected, 3);
      nav.handleInput(KEYS["tui.select.pageUp"], keybindings, rows, 3);
      assert.equal(state().selected, 0);
    });

    test("drops a detail whose row went away", () => {
      const nav = new DrillDown(() => {});
      nav.sync(["one", "two"], (row) => row);
      nav.handleInput(KEYS["tui.select.down"], keybindings, ["one", "two"], 10);
      nav.handleInput(
        KEYS["tui.select.confirm"],
        keybindings,
        ["one", "two"],
        10,
      );
      assert.equal(nav.sync(["one", "two"], (row) => row).detail, "two");

      assert.equal(nav.sync(["one"], (row) => row).detail, undefined);
      assert.equal(nav.sync(["one"], (row) => row).selected, 0);
    });

    test("shows the end of a detail and follows it as lines arrive", () => {
      const nav = new DrillDown(() => {});
      const openDetail = () => {
        nav.sync(["job"], (row) => row);
        nav.handleInput(KEYS["tui.select.confirm"], keybindings, ["job"], 10);
      };

      openDetail();
      assert.equal(nav.detailWindow(20, 5), 15);
      assert.equal(nav.detailWindow(22, 5), 17, "a followed end moves with it");
    });

    test("pins the detail where the reader scrolled, until the end", () => {
      // The overlay renders the detail before a key moves it, so the window is
      // measured first.
      const nav = new DrillDown(() => {});
      nav.sync(["job"], (row) => row);
      nav.handleInput(KEYS["tui.select.confirm"], keybindings, ["job"], 10);
      assert.equal(nav.detailWindow(20, 5), 15);

      nav.handleInput(KEYS["tui.select.up"], keybindings, ["job"], 5);
      assert.equal(nav.detailWindow(20, 5), 14);
      assert.equal(nav.detailWindow(24, 5), 14, "a pinned window stays put");

      for (let press = 0; press < 5; press += 1) {
        nav.handleInput(KEYS["tui.select.pageUp"], keybindings, ["job"], 5);
      }
      assert.equal(nav.detailWindow(20, 5), 0, "scrolling stops at the top");

      for (let press = 0; press < 5; press += 1) {
        nav.handleInput(KEYS["tui.select.pageDown"], keybindings, ["job"], 5);
      }
      assert.equal(nav.detailWindow(20, 5), 15, "the end follows again");
    });

    test("follows the end again after the detail shrinks to fit", () => {
      const nav = new DrillDown(() => {});
      nav.sync(["job"], (row) => row);
      nav.handleInput(KEYS["tui.select.confirm"], keybindings, ["job"], 10);
      nav.detailWindow(20, 5);
      nav.handleInput(KEYS["tui.select.up"], keybindings, ["job"], 5);
      assert.equal(nav.detailWindow(20, 5), 14, "the reader pinned the window");

      assert.equal(
        nav.detailWindow(3, 5),
        0,
        "a detail that fits starts at the top",
      );
      assert.equal(
        nav.detailWindow(20, 5),
        15,
        "and follows the end when it grows again",
      );
    });
  });

  describe("padding", () => {
    test("pads to a terminal width and leaves wider text alone", () => {
      assert.equal(padRight("ab", 5), "ab   ");
      assert.equal(padRight("abcdef", 5), "abcdef");
      assert.equal(padLeft("ab", 5), "   ab");
      assert.equal(padLeft("abcdef", 5), "abcdef");
    });
  });

  describe("list rows", () => {
    /**
     * A theme that records what a row is styled with, and leaves its text.
     *
     * @returns The theme, and the `fg`, `bold` and `bg` calls it received.
     */
    function recordingTheme() {
      const calls = { fg: [], bold: [], bg: [] };
      const theme = {
        fg: (color, text) => {
          calls.fg.push({ color, text });
          return text;
        },
        bold: (text) => {
          calls.bold.push(text);
          return text;
        },
        bg: (color, text) => {
          calls.bg.push({ color, text });
          return text;
        },
      };
      return { calls, theme };
    }

    test("marks the cursor row with the cursor, a bold label and the band", () => {
      const { calls, theme } = recordingTheme();
      const line = listRow(theme, "timer-a", ["running", "00:12"], 24, true);

      assert.equal(
        textOf([line]).trimEnd(),
        `${SELECTED_CURSOR} timer-a running 00:12`,
      );
      assert.equal(visibleWidth(line), 24, "the row fills the body width");
      assert.deepEqual(calls.bold, ["timer-a"], "the label is bold");
      assert.deepEqual(
        calls.bg,
        [{ color: "selectedBg", text: line }],
        "the band covers the padding too",
      );
      assert.deepEqual(
        calls.fg,
        [{ color: "accent", text: SELECTED_CURSOR }],
        "the accent marks the cursor only, so the label keeps its text color",
      );
    });

    test("leaves every other row plain and aligned with the cursor row", () => {
      const { calls, theme } = recordingTheme();
      const selected = listRow(theme, "timer-a", ["running"], 20, true);
      const other = listRow(theme, "timer-b", ["running"], 20, false);

      assert.deepEqual(
        calls.bold,
        ["timer-a"],
        "only the cursor row's label is bold",
      );
      assert.deepEqual(
        calls.bg.map((entry) => entry.color),
        ["selectedBg"],
        "only the cursor row is painted",
      );
      assert.equal(
        visibleWidth(other),
        20,
        "the plain row still fills the body",
      );
      assert.equal(
        textOf([other]).indexOf("running"),
        textOf([selected]).indexOf("running"),
        "the cursor column keeps the columns aligned",
      );
    });

    test("cuts a row wider than the body before painting it", () => {
      const { calls, theme } = recordingTheme();
      const line = listRow(theme, "a".repeat(30), [], 10, true);

      assert.equal(visibleWidth(line), 10);
      assert.match(textOf([line]), /\.\.\.$/);
      assert.equal(
        calls.bg[0].text,
        line,
        "the band wraps the cut, padded row",
      );
    });
  });
});
