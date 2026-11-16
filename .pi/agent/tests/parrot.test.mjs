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
  LOGO_DELAY_MS,
  MORPH_STEPS,
  MOTION_PERIOD_TICKS,
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

function bounds(grid) {
  const cells = colored(grid);
  return {
    top: Math.min(...cells.map((cell) => cell.row)),
    bottom: Math.max(...cells.map((cell) => cell.row)),
    left: Math.min(...cells.map((cell) => cell.col)),
    right: Math.max(...cells.map((cell) => cell.col)),
  };
}

/** Interior gaps: transparent cells with a lit cell on both sides. */
function holes(grid) {
  const gaps = (line) => {
    const lit = line.flatMap((pixel, index) => (pixel === null ? [] : [index]));
    if (lit.length < 2) return [];
    const span = Array.from(
      { length: lit.at(-1) - lit[0] + 1 },
      (_, offset) => lit[0] + offset,
    );
    return span.filter((index) => line[index] === null);
  };

  const found = [];
  grid.forEach((row, rowIndex) => {
    for (const col of gaps(row)) found.push(`row ${rowIndex}, col ${col}`);
  });
  for (let col = 0; col < grid[0].length; col++) {
    for (const rowIndex of gaps(grid.map((row) => row[col]))) {
      found.push(`row ${rowIndex}, col ${col}`);
    }
  }
  return found;
}

/** Animated frames of one motion, one per tick. */
function framesFor(motion, count) {
  return Array.from(
    { length: count },
    (_, tick) =>
      frameFor(ANIMATION_START_MS + tick * FRAME_INTERVAL_MS, motion).grid,
  );
}

/** Ticks long enough to cover every motion's cycle twice. */
const CYCLE_TICKS = Math.max(...Object.values(MOTION_PERIOD_TICKS)) * 2;

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
    test("the logo shows until the morph starts", () => {
      assert.equal(frameFor(0, "flap").phase, "logo");
      assert.equal(frameFor(LOGO_DELAY_MS - 1, "flap").phase, "logo");
      assert.equal(frameFor(LOGO_DELAY_MS, "flap").phase, "morph");
      assert.equal(frameFor(ANIMATION_START_MS - 1, "flap").phase, "morph");
      assert.equal(frameFor(ANIMATION_START_MS, "flap").phase, "animate");

      const logo = frameFor(0, "flap").grid;
      assert.equal(logo.length, CANVAS_HEIGHT_PX);
      assert.ok(logo.every((row) => row.length === CANVAS_WIDTH_PX));
      assertCanvas(logo, PI_LOGO, 0, 0);
    });

    test("the logo is rendered with its exact half-block colors", () => {
      const [top, bottom] = renderCanvas(frameFor(0, "flap").grid, "truecolor");

      // Top-left cell stacks coral over blue, like pi's own logo.
      assert.ok(
        top.startsWith(`\x1b[38;2;228;138;122m\x1b[48;2;79;142;179m▀\x1b[0m`),
      );
      assert.ok(top.includes("\x1b[38;2;228;138;122m█\x1b[0m"));
      assert.ok(bottom.includes("\x1b[38;2;234;182;93m█\x1b[0m"));
      assert.equal(visibleWidth(top), CANVAS_WIDTH_PX);
      assert.equal(visibleWidth(bottom), CANVAS_WIDTH_PX);
    });

    test("the morph progresses and hands over without a jump", () => {
      const morphed = Array.from(
        { length: MORPH_STEPS },
        (_, index) =>
          frameFor(LOGO_DELAY_MS + index * FRAME_INTERVAL_MS, "flap").grid,
      );

      assert.ok(
        new Set(morphed.map(signature)).size > 1,
        "the morph does not move",
      );
      assert.notEqual(
        signature(morphed[0]),
        signature(frameFor(0, "flap").grid),
      );

      // It lands on the intact parrot, and every motion opens on that frame.
      assertCanvas(morphed.at(-1), PARROT, PARROT_TOP, PARROT_LEFT);
      for (const motion of MOTIONS) {
        assert.equal(
          signature(frameFor(ANIMATION_START_MS, motion).grid),
          signature(morphed.at(-1)),
          `${motion} does not open on the frame the morph ended with`,
        );
      }
    });

    test("every animated frame keeps the bird solid and on canvas", () => {
      for (const motion of MOTIONS) {
        for (const [tick, grid] of framesFor(motion, CYCLE_TICKS).entries()) {
          assert.deepEqual(
            holes(grid),
            [],
            `${motion} opened a hole at tick ${tick}`,
          );

          const box = bounds(grid);
          assert.ok(box.top >= 0, `${motion} tick ${tick} left the top`);
          assert.ok(
            box.bottom < CANVAS_HEIGHT_PX,
            `${motion} tick ${tick} left the bottom`,
          );
          assert.ok(box.left >= 0, `${motion} tick ${tick} left the canvas`);
          assert.ok(
            box.right < CANVAS_WIDTH_PX,
            `${motion} tick ${tick} left the canvas`,
          );
        }
      }
    });

    test("every motion moves, and repeats on its own cycle", () => {
      for (const motion of MOTIONS) {
        const period = MOTION_PERIOD_TICKS[motion];
        const cycle = framesFor(motion, period).map(signature);

        assert.ok(new Set(cycle).size > 1, `${motion} never moves`);
        assert.deepEqual(
          framesFor(motion, period * 2)
            .slice(period)
            .map(signature),
          cycle,
          `${motion} does not repeat`,
        );
      }
    });

    test("typing at any point ends the greeting on the logo", () => {
      const shatterAts = [
        FRAME_INTERVAL_MS, // during the logo
        LOGO_DELAY_MS + 4 * FRAME_INTERVAL_MS, // mid-morph
        ANIMATION_START_MS + 3 * FRAME_INTERVAL_MS, // while animating
      ];

      for (const motion of MOTIONS) {
        for (const shatterAt of shatterAts) {
          const landed = shatterAt + MORPH_STEPS * FRAME_INTERVAL_MS;

          for (const elapsed of [landed, landed + 60_000]) {
            const frame = frameFor(elapsed, motion, shatterAt);
            assert.equal(frame.phase, "logo", `${motion} at ${shatterAt}`);
            assertCanvas(frame.grid, PI_LOGO, 0, 0);
          }
        }
      }
    });
  });

  describe("extension", () => {
    /** Columns the two lines beside the brand cell start their text at. */
    const brandTextColumns = (lines) => [
      plain(lines[0]).indexOf(`v${VERSION}`),
      plain(lines[1]).indexOf("interrupt"),
    ];

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
      assert.ok(narrow[0].includes("\x1b[38;2;228;138;122m"));
      assert.ok(narrow[0].includes("\x1b[0m"));
    });

    test("the bird is drawn over the text, which never moves", (t) => {
      mockTimers(t);
      const session = startSession();
      const header = session.header();
      t.mock.timers.tick(ANIMATION_START_MS);

      const columns = brandTextColumns(header.render(120));
      const onboarding = plain(header.render(120)[2]);
      let drawnOverText = false;

      for (let tick = 0; tick < CYCLE_TICKS; tick++) {
        const lines = header.render(120);

        assert.deepEqual(
          brandTextColumns(lines),
          columns,
          `tick ${tick} moved the text`,
        );
        assert.equal(
          plain(lines[2]).slice(TEXT_SCREEN_COLUMN),
          onboarding.slice(TEXT_SCREEN_COLUMN),
          `tick ${tick} covered text past the brand cell`,
        );
        drawnOverText ||= blockColumns(lines[2]).length > 0;

        t.mock.timers.tick(FRAME_INTERVAL_MS);
      }

      assert.ok(drawnOverText, "the bird never shared a row with the text");
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
        ANIMATION_START_MS - LOGO_DELAY_MS + CYCLE_TICKS * FRAME_INTERVAL_MS;
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
      t.mock.timers.tick(MORPH_STEPS * FRAME_INTERVAL_MS);
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

    test("the motion is picked once per session, at random", (t) => {
      mockTimers(t);
      // Pin the motion so both sessions greet alike.
      t.mock.method(Math, "random", () => 0);
      const session = startSession();
      const first = session.header();
      const elapsed = ANIMATION_START_MS + 3 * FRAME_INTERVAL_MS;

      startSession();
      assert.equal(random.mock.callCount(), 1);

      // A reload is a new pick, and a session already under way gets none.
      const reloaded = startSession();
      reloaded.restart();
      assert.equal(random.mock.callCount(), 3);
      startSession(CONVERSATION);
      assert.equal(random.mock.callCount(), 3);
    });

    test("the motion is picked once per session, at random", (t) => {
      mockTimers(t);
      const random = t.mock.method(Math, "random", () => 0);

      startSession();
      assert.equal(random.mock.callCount(), 1);

      // A reload is a new pick, and a session already under way gets none.
      const reloaded = startSession();
      reloaded.restart();
      assert.equal(random.mock.callCount(), 3);
      startSession(CONVERSATION);
      assert.equal(random.mock.callCount(), 3);
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
