/**
 * The test may only test basic contracts and rules of parrot greeting
 * animation, but never the detail of its actual poses.
 *
 * A test here may pin what a caller can rely on: which phase shows when the
 * animation starts and ends, that typing ends the greeting on the logo, that
 * the bird stays on its canvas, that Pi's own text keeps its columns and
 * wraps, and that the frame clock runs only while something moves.
 *
 * A test here may not pin what a pose or a flight looks like: which pixels a
 * motion recolors, where a note starts, how fast it climbs, which glyph comes
 * next. Those are art, free to change with the next doodle, so they are
 * checked by looking at the bird, not by asserting on it.
 */

import assert from "node:assert/strict";
import test, { describe } from "node:test";

import { VERSION } from "@earendil-works/pi-coding-agent";
import { visibleWidth } from "@earendil-works/pi-tui";

import parrot, {
  ANIMATION_START_MS,
  CANVAS_HEIGHT_PX,
  CANVAS_WIDTH_PX,
  FRAME_INTERVAL_MS,
  frameFor,
  INTRO_TICKS,
  LOGO_DELAY_MS,
  MOTIONS,
  PALETTE,
  PARROT,
  PARROT_LEFT,
  PARROT_TOP,
  PI_LOGO,
  renderCanvas,
} from "../extensions/parrot.ts";

const colorKey = (rgb) => rgb.join(",");

/** Pi's built-in header margin, which this header reproduces. */
const HEADER_PADDING_X = 1;

/** Screen column of the text beside the brand cell. */
const TEXT_SCREEN_COLUMN = HEADER_PADDING_X + PI_LOGO[0].length + 1;

/** Terminal rows the brand cell occupies. */
const CANVAS_ROWS = CANVAS_HEIGHT_PX / 2;

/** The logo and morph phases ignore the motion, so any one renders them. */
const MOTION = MOTIONS[0];

/** A motion's class name, for readable failure messages. */
const motionName = (motion) => motion.constructor.name;

/** A session that already holds a conversation. */
const CONVERSATION = [
  { type: "message", message: { role: "user", content: "hi" } },
];

/** Colored canvas cells, row-major. */
function colored(grid) {
  const cells = [];
  for (let row = 0; row < grid.length; row++) {
    for (let col = 0; col < grid[row].length; col++) {
      if (grid[row][col] !== null) {
        cells.push({ row, col, color: colorKey(grid[row][col]) });
      }
    }
  }
  return cells;
}

/** Stable identity of a frame, for exact frame comparisons. */
function signature(grid) {
  return colored(grid)
    .map(({ row, col, color }) => `${row}:${col}:${color}`)
    .join("|");
}

/** The bitmap's colored cells, keyed by `row:col` at the given offset. */
function bitmapCells(bitmap, top, left) {
  const cells = new Map();
  bitmap.forEach((line, row) => {
    [...line].forEach((char, col) => {
      if (char !== ".") {
        cells.set(`${top + row}:${left + col}`, colorKey(PALETTE[char]));
      }
    });
  });
  return cells;
}

/** Assert the canvas shows exactly this bitmap, at this offset. */
function assertCanvas(target, bitmap, top, left) {
  const expected = bitmapCells(bitmap, top, left);
  const actual = colored(target);

  assert.equal(actual.length, expected.size);
  for (const { row, col, color } of actual) {
    assert.equal(
      color,
      expected.get(`${row}:${col}`),
      `unexpected pixel at ${row},${col}`,
    );
  }
}

/** The box the lit cells occupy, in canvas pixels. */
function bounds(grid) {
  const cells = colored(grid);
  return {
    top: Math.min(...cells.map((cell) => cell.row)),
    bottom: Math.max(...cells.map((cell) => cell.row)),
    left: Math.min(...cells.map((cell) => cell.col)),
    right: Math.max(...cells.map((cell) => cell.col)),
  };
}

/** Time since session_start of a tick of the loop. */
const loopAt = (tick) => ANIMATION_START_MS + tick * FRAME_INTERVAL_MS;

/** Time since session_start of a tick of the intro. */
const introAt = (tick) => LOGO_DELAY_MS + tick * FRAME_INTERVAL_MS;

/** Loop frames of one motion, one per tick. */
function loopFrames(motion, count) {
  return Array.from(
    { length: count },
    (_, tick) => frameFor(loopAt(tick), motion).grid,
  );
}

/** Ticks long enough to watch any motion's loop come round twice. */
const LOOP_TICKS = 60;

/** Install the extension and return the event hooks it registered. */
function loadExtension() {
  const hooks = new Map();
  parrot({ on: (name, handler) => hooks.set(name, handler) });
  return hooks;
}

/** Session context capturing the header slot, the input hook, and entries. */
function tuiContext(entries = []) {
  const state = { headers: [], factory: undefined, input: undefined };
  const ctx = {
    mode: "tui",
    ui: {
      setHeader: (factory) => {
        state.headers.push(factory);
        state.factory = factory;
      },
      onTerminalInput: (handler) => {
        state.input = handler;
        return () => {
          state.input = undefined;
        };
      },
    },
    sessionManager: { getEntries: () => entries },
  };
  return { ctx, state };
}

const plainTheme = {
  getColorMode: () => "truecolor",
  fg: (_color, text) => text,
};

/** A started session, with a TUI stub that counts requested renders. */
function startSession(entries = []) {
  const hooks = loadExtension();
  const { ctx, state } = tuiContext(entries);
  const counted = { renders: 0 };
  const tui = {
    requestRender: () => {
      counted.renders += 1;
    },
  };

  hooks.get("session_start")({}, ctx);
  return {
    hooks,
    state,
    counted,
    header: () => state.factory(tui, plainTheme),
    restart: () => hooks.get("session_start")({}, ctx),
  };
}

/** The clocks the animation runs on: its delayed start, its frames, and time. */
const mockTimers = (t) =>
  t.mock.timers.enable({
    apis: ["setTimeout", "setInterval", "Date"],
    now: 0,
  });

/** A line with its ANSI styling and hyperlink sequences stripped. */
const plain = (line) => line.replace(/\x1b(?:\[[0-9;]*m|\]8;;\x07)/g, "");

/** Visible content in reading order, ignoring whitespace and line breaks. */
const squash = (lines) => lines.map(plain).join("").replace(/\s+/g, "");

/** Screen columns where a line draws half-block glyphs. */
const blockColumns = (line) =>
  [...plain(line)].flatMap((char, column) =>
    /[▀▄█]/.test(char) ? [column] : [],
  );

/** The brand cell's glyphs, row by row. */
const brandCell = (lines) =>
  lines
    .slice(0, CANVAS_ROWS)
    .map((line) =>
      plain(line).slice(HEADER_PADDING_X, HEADER_PADDING_X + PARROT[0].length),
    );

describe("parrot", () => {
  describe("canvas", () => {
    test("the logo, the intro, the loop, then the outro run in that order", () => {
      for (const motion of MOTIONS) {
        assert.equal(frameFor(0, motion).phase, "logo");
        assert.equal(frameFor(LOGO_DELAY_MS - 1, motion).phase, "logo");
        assert.equal(frameFor(LOGO_DELAY_MS, motion).phase, "intro");
        assert.equal(frameFor(ANIMATION_START_MS - 1, motion).phase, "intro");
        assert.equal(frameFor(ANIMATION_START_MS, motion).phase, "loop");
        assert.equal(frameFor(loopAt(60_000), motion).phase, "loop");

        const logo = frameFor(0, motion).grid;
        assert.equal(logo.length, CANVAS_HEIGHT_PX);
        assert.ok(logo.every((row) => row.length === CANVAS_WIDTH_PX));
        assertCanvas(logo, PI_LOGO, 0, 0);
      }
    });

    test("the logo is rendered with its exact half-block colors", () => {
      const [top, bottom] = renderCanvas(frameFor(0, MOTION).grid, "truecolor");
      const fg = (key) => `\x1b[38;2;${PALETTE[key].join(";")}m`;
      const bg = (key) => `\x1b[48;2;${PALETTE[key].join(";")}m`;

      // Top-left cell stacks coral over blue, like pi's own logo.
      assert.ok(top.startsWith(`${fg("C")}${bg("B")}▀\x1b[0m`));
      assert.ok(top.includes(`${fg("C")}█\x1b[0m`));
      assert.ok(bottom.includes(`${fg("Y")}█\x1b[0m`));
      assert.equal(visibleWidth(top), CANVAS_WIDTH_PX);
      assert.equal(visibleWidth(bottom), CANVAS_WIDTH_PX);
    });

    test("the intro recomposes the logo and hands over to every motion", () => {
      const intro = Array.from(
        { length: INTRO_TICKS },
        (_, tick) => frameFor(introAt(tick), MOTION).grid,
      );
      assert.ok(
        new Set(intro.map(signature)).size > 1,
        "the intro does not move",
      );
      assert.notEqual(
        signature(intro[0]),
        signature(frameFor(0, MOTION).grid),
        "the intro starts on the logo it leaves behind",
      );
      assertCanvas(intro.at(-1), PARROT, PARROT_TOP, PARROT_LEFT);

      for (const motion of MOTIONS) {
        // The loop opens on the parrot the intro ended with, and the outro
        // opens on the same one.
        const opening = signature(frameFor(ANIMATION_START_MS, motion).grid);
        assert.equal(
          signature(
            frameFor(ANIMATION_START_MS - FRAME_INTERVAL_MS, motion).grid,
          ),
          opening,
          `${motionName(motion)} jumps when the intro hands over`,
        );
        assertCanvas(
          frameFor(ANIMATION_START_MS, motion).grid,
          PARROT,
          PARROT_TOP,
          PARROT_LEFT,
        );
      }
    });

    test("every loop moves and repeats, without being told its cycle", () => {
      for (const motion of MOTIONS) {
        const frames = loopFrames(motion, LOOP_TICKS).map(signature);
        assert.ok(
          new Set(frames).size > 1,
          `${motionName(motion)} never moves`,
        );

        // The first period after which the whole window agrees with itself.
        const period = frames.findIndex(
          (_frame, candidate) =>
            candidate > 0 &&
            frames.every(
              (frame, tick) =>
                tick + candidate >= frames.length ||
                frame === frames[tick + candidate],
            ),
        );
        assert.ok(period > 0, `${motionName(motion)} never repeats`);
      }
    });

    test("typing during the loop flies home to the logo", () => {
      for (const motion of MOTIONS) {
        const typed = loopAt(3);

        // The outro flies the resting parrot home, dropping whatever pose the
        // loop was showing when the user typed.
        assert.equal(
          signature(frameFor(typed, motion, typed).grid),
          signature(frameFor(introAt(INTRO_TICKS - 1), motion).grid),
          `${motionName(motion)} does not fly home from the resting parrot`,
        );

        const landed = typed + INTRO_TICKS * FRAME_INTERVAL_MS;
        for (const elapsed of [landed, landed + 60_000]) {
          const frame = frameFor(elapsed, motion, typed);
          assert.equal(
            frame.phase,
            "logo",
            `${motionName(motion)} at ${typed}`,
          );
          assertCanvas(frame.grid, PI_LOGO, 0, 0);
        }
      }
    });

    test("typing mid-intro flies home from the step on screen", () => {
      for (let tick = 0; tick < INTRO_TICKS; tick++) {
        const typed = introAt(tick);
        assert.equal(
          signature(frameFor(typed, MOTION, typed).grid),
          signature(frameFor(typed, MOTION).grid),
          `typing at intro tick ${tick} jumped`,
        );

        // One tick of outro per step of intro already on screen.
        const landed = typed + (tick + 1) * FRAME_INTERVAL_MS;
        assert.equal(
          frameFor(landed, MOTION, typed).phase,
          "logo",
          `intro tick ${tick} did not land on the logo`,
        );
      }

      // Typing under the logo needs no outro at all.
      const typed = FRAME_INTERVAL_MS;
      assert.equal(frameFor(typed, MOTION, typed).phase, "logo");
      assertCanvas(frameFor(typed, MOTION, typed).grid, PI_LOGO, 0, 0);
    });

    test("every frame of a greeting stays on the canvas", () => {
      const typed = loopAt(5);
      const times = [
        ...Array.from({ length: INTRO_TICKS }, (_, tick) => introAt(tick)),
        ...Array.from({ length: LOOP_TICKS }, (_, tick) => loopAt(tick)),
        ...Array.from(
          { length: INTRO_TICKS + 1 },
          (_, tick) => typed + tick * FRAME_INTERVAL_MS,
        ),
      ];

      for (const motion of MOTIONS) {
        for (const [tick, elapsed] of times.entries()) {
          const box = bounds(frameFor(elapsed, motion).grid);
          assert.ok(
            box.top >= 0,
            `${motionName(motion)} tick ${tick} left the top`,
          );
          assert.ok(
            box.bottom < CANVAS_HEIGHT_PX,
            `${motionName(motion)} tick ${tick} left the bottom`,
          );
          assert.ok(
            box.left >= 0,
            `${motionName(motion)} tick ${tick} left the canvas`,
          );
          assert.ok(
            box.right < CANVAS_WIDTH_PX,
            `${motionName(motion)} tick ${tick} left the canvas`,
          );
        }
      }
    });
  });

  describe("extension", () => {
    test("the header reproduces Pi's built-in layout", (t) => {
      mockTimers(t);
      const session = startSession();
      const lines = session.header().render(120);

      assert.equal(lines.length, 5);
      assert.ok(lines[0].includes(`v${VERSION}`));
      assert.ok(lines[1].includes("commands"));
      assert.ok(lines[2].includes("Press"));
      assert.equal(plain(lines[3]).trim(), "");
      assert.ok(lines[4].includes("Pi can explain its own features"));

      // Pi's margin, and its text columns beside the brand cell.
      assert.equal(plain(lines[0]).indexOf(`v${VERSION}`), TEXT_SCREEN_COLUMN);
      assert.ok(plain(lines[1]).indexOf("interrupt") > TEXT_SCREEN_COLUMN);
      assert.ok(
        plain(lines[2]).startsWith(" ".repeat(HEADER_PADDING_X)),
        "the onboarding line lost Pi's margin",
      );

      // A narrow render keeps the brand ANSI escape sequences.
      const narrow = session.header().render(8);
      assert.ok(narrow[0].includes(`\x1b[38;2;${PALETTE.C.join(";")}m`));
      assert.ok(narrow[0].includes("\x1b[0m"));
    });

    test("the bird is drawn over the text, which keeps its columns", (t) => {
      mockTimers(t);
      const session = startSession();
      const header = session.header();

      /** One word per header row, to read that row's columns back by. */
      const probes = [
        { row: 0, word: `v${VERSION}` },
        { row: 1, word: "interrupt" },
        { row: 2, word: "Press" },
        { row: 4, word: "Pi can explain" },
      ];
      const columnsOf = (lines) =>
        probes.map(({ row, word }) => plain(lines[row]).indexOf(word));

      // Measured under the logo, before anything is in the air to hide a word.
      const columns = columnsOf(header.render(120));
      assert.ok(
        columns.every((column) => column !== -1),
        "a probe word is not in Pi's header any more",
      );
      t.mock.timers.tick(ANIMATION_START_MS);

      let drawnOverText = false;

      for (let tick = 0; tick < LOOP_TICKS; tick++) {
        const lines = header.render(120);

        // A glyph flying in front may hide a word for a few frames; a word
        // that is visible is still in its own column, on a row that still fits.
        assert.ok(
          lines.every((line) => visibleWidth(line) <= 120),
          `tick ${tick} overran the width`,
        );
        const seen = columnsOf(lines);
        for (let probe = 0; probe < probes.length; probe++) {
          if (seen[probe] === -1) continue;
          assert.equal(
            seen[probe],
            columns[probe],
            `tick ${tick} moved "${probes[probe].word}"`,
          );
        }

        drawnOverText ||= lines.some((line) => blockColumns(line).length > 0);

        t.mock.timers.tick(FRAME_INTERVAL_MS);
      }

      assert.ok(drawnOverText, "the bird never drew over the text");
    });

    test("a narrow terminal wraps like Pi's header", (t) => {
      mockTimers(t);
      const session = startSession();
      const header = session.header();
      t.mock.timers.tick(ANIMATION_START_MS);

      const wide = header.render(120);
      // The closing hint never shares a row with the bird, so reflowing must
      // hand it back intact.
      const closing = squash([wide.at(-1)]);

      for (const width of [80, 50, 32, 16, 8]) {
        const narrow = header.render(width);
        assert.ok(narrow.length > wide.length, `width ${width} did not reflow`);

        for (const line of narrow) {
          assert.ok(
            visibleWidth(line) <= width,
            `width ${width} exceeded by "${line}"`,
          );
        }

        narrow.forEach((line, row) => {
          // The bird stays inside its own cell, whichever row it floats to.
          for (const column of blockColumns(line)) {
            assert.ok(
              row < CANVAS_ROWS,
              `width ${width} drew the bird on row ${row}`,
            );
            assert.ok(
              column >= HEADER_PADDING_X &&
                column < HEADER_PADDING_X + PARROT[0].length,
              `width ${width} row ${row} drew the bird at column ${column}`,
            );
          }

          // Below the bird the text uses Pi's full width, not an indent.
          if (row < CANVAS_ROWS || plain(line).trim() === "") return;
          assert.notEqual(
            plain(line)[HEADER_PADDING_X],
            " ",
            `width ${width} row ${row} indented past the margin`,
          );
        });

        assert.ok(
          squash(narrow).includes(closing),
          `width ${width} lost the closing hint`,
        );
      }

      // A pathological width still fits, dropping the margin like Pi's Text.
      for (const line of header.render(1)) {
        assert.ok(visibleWidth(line) <= 1, `"${line}" exceeds one column`);
      }
    });

    test("the frame clock runs only while the animation moves", (t) => {
      mockTimers(t);
      const session = startSession();
      session.header();

      // The opening logo is static, so nothing is requested before the morph.
      t.mock.timers.tick(LOGO_DELAY_MS - FRAME_INTERVAL_MS);
      assert.equal(session.counted.renders, 0);

      t.mock.timers.tick(FRAME_INTERVAL_MS);
      assert.equal(session.counted.renders, 1);

      const morphAndMotion =
        ANIMATION_START_MS - LOGO_DELAY_MS + LOOP_TICKS * FRAME_INTERVAL_MS;
      t.mock.timers.tick(morphAndMotion);
      assert.ok(
        session.counted.renders > 2,
        "the clock stopped while the bird was moving",
      );
    });

    test("typing stops the animation for the rest of the session", (t) => {
      mockTimers(t);
      const session = startSession();
      const header = session.header();
      const logoCell = brandCell(header.render(120));

      t.mock.timers.tick(ANIMATION_START_MS);

      // Scrolling, interrupts, and submitting are not typing: the bird stays.
      for (const data of ["\x1b[A", "\x1b[5~", "\x03", "\x7f", "\r"]) {
        assert.equal(
          session.state.input(data),
          undefined,
          `"${data}" was consumed`,
        );
      }
      t.mock.timers.tick(FRAME_INTERVAL_MS);
      assert.notDeepEqual(brandCell(header.render(120)), logoCell);

      // A typed character ends the greeting, and the header keeps the logo.
      assert.equal(session.state.input("h"), undefined);
      t.mock.timers.tick(INTRO_TICKS * FRAME_INTERVAL_MS);
      assert.deepEqual(brandCell(header.render(120)), logoCell);

      // The clock stops for good, the listener goes, the bird never returns.
      const rendersAtRest = session.counted.renders;
      t.mock.timers.tick(60_000);
      assert.equal(session.counted.renders, rendersAtRest);
      assert.deepEqual(brandCell(header.render(120)), logoCell);
      assert.equal(session.state.input, undefined);
    });

    test("typing during the logo phase skips the greeting entirely", (t) => {
      mockTimers(t);
      const session = startSession();
      const header = session.header();
      const logoCell = brandCell(header.render(120));

      session.state.input("h");
      t.mock.timers.tick(ANIMATION_START_MS);

      assert.equal(session.counted.renders, 0, "a static logo needs no clock");
      assert.deepEqual(brandCell(header.render(120)), logoCell);
      assert.equal(session.state.input, undefined);
    });

    test("a session already under way keeps Pi's header", (t) => {
      mockTimers(t);
      const session = startSession(CONVERSATION);

      assert.deepEqual(session.state.headers, [undefined]);
      assert.equal(session.state.input, undefined);
      t.mock.timers.tick(ANIMATION_START_MS + FRAME_INTERVAL_MS);
      assert.equal(session.counted.renders, 0);
    });

    test("the frame clock starts once per session", (t) => {
      mockTimers(t);
      const session = startSession();
      session.header();

      // The clock starts with the morph, not with the static logo.
      t.mock.timers.tick(LOGO_DELAY_MS);
      assert.equal(session.counted.renders, 1);
      t.mock.timers.tick(FRAME_INTERVAL_MS);
      assert.equal(session.counted.renders, 2);

      // A reloaded empty session greets again on a single clock: had the old
      // interval survived, these renders would double up.
      session.restart();
      session.header();
      t.mock.timers.tick(LOGO_DELAY_MS);
      assert.equal(session.counted.renders, 3);
      t.mock.timers.tick(FRAME_INTERVAL_MS);
      assert.equal(session.counted.renders, 4);
    });

    test("the random pick chooses the motion a session plays", (t) => {
      mockTimers(t);
      const random = t.mock.method(Math, "random", () => 0);

      // Each stubbed value selects another motion, and each session plays the
      // motion it picked for a whole cycle: every bird sings its own tune, not
      // one repeated greeting.
      const played = MOTIONS.map((_motion, index) => {
        random.mock.mockImplementation(() => (index + 0.5) / MOTIONS.length);
        const session = startSession();
        const header = session.header();
        t.mock.timers.tick(ANIMATION_START_MS);

        return Array.from({ length: LOOP_TICKS }, () => {
          const cell = brandCell(header.render(120));
          t.mock.timers.tick(FRAME_INTERVAL_MS);
          return cell;
        });
      });
      assert.equal(random.mock.callCount(), MOTIONS.length);

      for (let first = 0; first < played.length; first++) {
        for (let second = first + 1; second < played.length; second++) {
          assert.notDeepEqual(
            played[first],
            played[second],
            `${motionName(MOTIONS[first])} plays like ${motionName(MOTIONS[second])}`,
          );
        }
      }

      // A reload picks again; a session already under way never does.
      const reloaded = startSession();
      reloaded.restart();
      assert.equal(random.mock.callCount(), MOTIONS.length + 2);
      startSession(CONVERSATION);
      assert.equal(random.mock.callCount(), MOTIONS.length + 2);
    });

    test("session_shutdown and dispose stop the frame clock", (t) => {
      mockTimers(t);
      const session = startSession();
      const header = session.header();

      t.mock.timers.tick(LOGO_DELAY_MS);
      assert.equal(session.counted.renders, 1);
      t.mock.timers.tick(FRAME_INTERVAL_MS * 3);
      assert.equal(session.counted.renders, 4);

      session.hooks.get("session_shutdown")();
      t.mock.timers.tick(FRAME_INTERVAL_MS * 5);
      assert.equal(session.counted.renders, 4);

      header.dispose();
      t.mock.timers.tick(FRAME_INTERVAL_MS * 5);
      assert.equal(session.counted.renders, 4);

      // A shutdown before the morph starts cancels the delayed clock too.
      const early = startSession();
      early.hooks.get("session_shutdown")();
      t.mock.timers.tick(ANIMATION_START_MS);
      assert.equal(early.counted.renders, 0);
    });

    test("non-TUI sessions keep the built-in header", (t) => {
      mockTimers(t);
      const hooks = loadExtension();
      const ctx = {
        mode: "rpc",
        ui: {
          setHeader: () => {
            throw new Error("must not replace the header outside the TUI");
          },
          onTerminalInput: () => {
            throw new Error("must not listen for input outside the TUI");
          },
        },
        sessionManager: {
          getEntries: () => {
            throw new Error("must not read the session outside the TUI");
          },
        },
      };

      hooks.get("session_start")({}, ctx);
      hooks.get("session_shutdown")();
    });
  });
});
