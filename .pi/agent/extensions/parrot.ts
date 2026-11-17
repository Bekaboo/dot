/**
 * Pi-rrot: the Pi logo gradually recomposes into a cute parrot!
 */

import type {
  ExtensionAPI,
  ExtensionContext,
  Theme,
} from "@earendil-works/pi-coding-agent";

import { keyText, VERSION } from "@earendil-works/pi-coding-agent";

import {
  backgroundAnsi,
  type Component,
  compositeTuiLine,
  foregroundAnsi,
  rgbColor,
  sliceByColumn,
  type TerminalColorMode,
  type TUI,
  truncateToWidth,
  visibleWidth,
  wrapTextWithAnsi,
} from "@earendil-works/pi-tui";

/** Brand palette shared by the logo and the parrot. */
export const PALETTE = {
  C: [228, 138, 122], // Pi coral
  B: [79, 142, 179], // Pi blue tail
  A: [146, 197, 224], // Azure wing, lighter than the tail it folds against
  Y: [234, 182, 93], // Pi yellow
  W: [245, 241, 232], // White face and upper beak
  K: [23, 36, 44], // Black lower beak
} as const satisfies Record<string, readonly [number, number, number]>;

type PaletteKey = keyof typeof PALETTE;
type Rgb = readonly [number, number, number];

/** One canvas of pixels; null is transparent. Rows pair up into terminal rows. */
export type Grid = (Rgb | null)[][];

/** The original Pi logo, 4 columns by 4 pixels. */
export const PI_LOGO = ["CCC.", "B.C.", "BB.Y", "B..Y"] as const;

/**
 * The parrot, 4 columns by 6 pixels: coral head and body, the body reaching
 * half a cell below the wing, white face, yellow chest, black beak, an azure
 * wing folded along the back, and a Pi blue tail.
 */
export const PARROT = [".CC.", ".CWW", "ACYK", "ACY.", "BC..", "B..."] as const;

export const FRAME_INTERVAL_MS = 120;
export const LOGO_DELAY_MS = 2000;
/** Ticks the intro and the outro each take: one morph step per tick. */
export const INTRO_TICKS = 10;
export const CANVAS_WIDTH_PX = 16;
/** Four terminal rows: the bird's three, plus one for it to float down into. */
export const CANVAS_HEIGHT_PX = 8;

/**
 * Canvas position of the resting parrot's top-left pixel: it lands on the same
 * brand cell the logo occupied, so the morph recomposes in place.
 */
export const PARROT_TOP = 0;
export const PARROT_LEFT = 0;

const INTRO_MS = INTRO_TICKS * FRAME_INTERVAL_MS;
export const ANIMATION_START_MS = LOGO_DELAY_MS + INTRO_MS;

/**
 * One glyph drawn in front of the header's text, in header rows and columns.
 * `Sing` produces them, `ParrotAnimation` composites them; what they are or
 * why they fly is not the header's business.
 *
 * @param row - Zero-based header row, counted from the top of the header.
 * @param col - Zero-based column of the header's content, the brand cell
 *   included: a glyph may fly well past the four columns the bird occupies.
 */
interface HeaderGlyph {
  readonly row: number;
  readonly col: number;
  readonly glyph: string;
}

/**
 * One greeting: three stretches of animation, each posed one tick at a time.
 *
 * `pose()` loops for as long as the user lets the bird play. `start()` and
 * `end()` are played once and glue the loop to the Pi logo: the intro
 * recomposes the logo into the parrot the loop opens on, the outro flies the
 * parrot back to within a step of the logo. Each returns the whole canvas for
 * its tick.
 */
export interface Motion {
  /**
   * Frames of the intro, ticks 0 through INTRO_TICKS - 1: the logo recomposing
   * into the resting parrot that `pose(0)` shows.
   */
  start(tick: number): Grid;
  /** Frames of the loop, one per tick, repeating on the motion's own cycle. */
  pose(tick: number): Grid;
  /**
   * Frames of the outro, ticks 0 through INTRO_TICKS - 1: from the resting
   * parrot `pose(0)` shows back to one morph step short of the logo, which the
   * logo phase then shows.
   */
  end(tick: number): Grid;
}

/** An empty canvas-tall grid, one column per parrot column. */
function poseGrid(): Grid {
  return Array.from({ length: CANVAS_HEIGHT_PX }, () =>
    Array.from({ length: PARROT[0].length }, () => null),
  );
}

/** The resting parrot on a canvas-tall grid, ready for a motion to pose. */
function restingPose(): Grid {
  const grid = poseGrid();
  placeGrid(grid, bitmapGrid(PARROT), 0, 0);
  return grid;
}

/**
 * Layout of Pi's built-in header, which this one reproduces: every line
 * carries a one-column margin, and the two lines beside the brand cell start
 * one past it. The bird is composited over the wrapped rows, so it may cover
 * their first characters rather than shift them.
 */
const HEADER_PADDING_X = 1;
const BRAND_TEXT_COLUMN = PI_LOGO[0].length + 1;
const RESET = "\x1b[0m";

/**
 * Half-block glyphs that pack two pixel rows into one terminal cell: upper
 * paints the top pixel only, lower the bottom pixel only, full both at once.
 */
const UPPER_HALF_BLOCK = "\u2580";
const LOWER_HALF_BLOCK = "\u2584";
const FULL_BLOCK = "\u2588";

/** Matches a cell the animation painted, as opposed to text or padding. */
const PAINTED_CELL = new RegExp(
  `[${UPPER_HALF_BLOCK}${LOWER_HALF_BLOCK}${FULL_BLOCK}]`,
);

/** Map a bitmap character to its palette color; null is transparent. */
function colorFor(char: string): Rgb | null {
  if (char === ".") return null;
  if (!(char in PALETTE)) throw new Error(`Unknown bitmap pixel: ${char}`);
  return PALETTE[char as PaletteKey];
}

/** Turn a character bitmap into a grid with exact dimensions. */
function bitmapGrid(rows: readonly string[]): Grid {
  return rows.map((row) => [...row].map(colorFor));
}

function emptyCanvas(): Grid {
  return Array.from({ length: CANVAS_HEIGHT_PX }, () =>
    Array.from({ length: CANVAS_WIDTH_PX }, () => null),
  );
}

/** Paint the non-transparent pixels of `source` at the given canvas offset. */
function placeGrid(
  target: Grid,
  source: Grid,
  top: number,
  left: number,
): void {
  for (let row = 0; row < source.length; row++) {
    for (let col = 0; col < source[row].length; col++) {
      const pixel = source[row][col];
      if (pixel !== null) target[top + row][left + col] = pixel;
    }
  }
}

function logoCanvas(): Grid {
  const canvas = emptyCanvas();
  placeGrid(canvas, bitmapGrid(PI_LOGO), 0, 0);
  return canvas;
}

interface BitmapPixel {
  readonly row: number;
  readonly col: number;
  readonly color: Rgb;
}

const PARROT_PIXELS: readonly BitmapPixel[] = PARROT.flatMap((line, row) =>
  [...line].flatMap((char, col) => {
    const color = colorFor(char);
    return color === null ? [] : [{ row, col, color }];
  }),
);

/** The head's pixels in PARROT coordinates, crown through beak. */
const HEAD_PIXELS: readonly (readonly [number, number])[] = [
  [0, 1],
  [0, 2],
  [1, 1],
  [1, 2],
  [1, 3],
  [2, 3],
];

/**
 * Pi-logo pixel each parrot pixel travels from, in PARROT_PIXELS order.
 *
 * The parrot has more colored pixels than the logo, so some parrot pixels
 * share a source and the extra ones grow out of the nearest matching color.
 */
const MORPH_SOURCES: readonly (readonly [number, number])[] = [
  [0, 1],
  [0, 2],
  [1, 2],
  [0, 0],
  [1, 2],
  [1, 0],
  [0, 2],
  [2, 3],
  [3, 3],
  [2, 0],
  [0, 1],
  [2, 3],
  [3, 0],
  [0, 1],
  [2, 1],
];

if (MORPH_SOURCES.length !== PARROT_PIXELS.length) {
  throw new Error("MORPH_SOURCES must map every parrot pixel");
}

function mixRgb(from: Rgb, to: Rgb, progress: number): Rgb {
  const channel = (index: number) =>
    Math.round(from[index] + (to[index] - from[index]) * progress);
  return [channel(0), channel(1), channel(2)];
}

/**
 * Interpolate one morph step: every parrot pixel travels from its Pi-logo
 * source while its color blends toward the parrot palette.
 *
 * @param step - Morph step, 1 through INTRO_TICKS.
 * @returns The canvas at `step / INTRO_TICKS` progress; the last step is the
 *   exact resting parrot.
 */
function morphCanvas(step: number): Grid {
  const progress = step / INTRO_TICKS;
  const canvas = emptyCanvas();

  for (let index = 0; index < PARROT_PIXELS.length; index++) {
    const pixel = PARROT_PIXELS[index];
    const [fromRow, fromCol] = MORPH_SOURCES[index];
    const sourceColor = colorFor(PI_LOGO[fromRow][fromCol]);
    if (sourceColor === null) {
      throw new Error(
        `MORPH_SOURCES points at transparent pixel ${fromRow},${fromCol}`,
      );
    }

    const targetRow = PARROT_TOP + pixel.row;
    const targetCol = PARROT_LEFT + pixel.col;
    const row = Math.round(fromRow + (targetRow - fromRow) * progress);
    const col = Math.round(fromCol + (targetCol - fromCol) * progress);
    canvas[row][col] = mixRgb(sourceColor, pixel.color, progress);
  }

  return canvas;
}

/** Place a motion's bird pixels on the canvas, where the morph left the bird. */
function birdCanvas(bird: Grid): Grid {
  const canvas = emptyCanvas();
  placeGrid(canvas, bird, PARROT_TOP, PARROT_LEFT);
  return canvas;
}

/**
 * The brand transition every motion shares: the intro recomposes the Pi logo
 * into the parrot and the outro flies it back, one morph step per tick.
 *
 * A motion only poses its loop; overriding a transition is for a motion that
 * wants to enter or leave the screen its own way.
 */
abstract class BrandMotion implements Motion {
  start(tick: number): Grid {
    return morphCanvas(tick + 1);
  }

  end(tick: number): Grid {
    return morphCanvas(INTRO_TICKS - tick);
  }

  abstract pose(tick: number): Grid;
}

/**
 * The wing flap: one azure cell rises above the back, then sweeps under the
 * belly, while the body floats a cell down on the upstroke.
 */
class Flap extends BrandMotion {
  private static readonly PERIOD_TICKS = 12;
  private static readonly REST_TICKS = 2;
  private static readonly UPSTROKE_TICKS = 5;
  private static readonly FLOAT_DROP_PX = 2;
  /** The wing's azure, against the Pi blue tail it folds above. */
  private static readonly WING = PALETTE.A;

  pose(tick: number): Grid {
    const phase = tick % Flap.PERIOD_TICKS;
    const up =
      phase >= Flap.REST_TICKS && phase < Flap.REST_TICKS + Flap.UPSTROKE_TICKS;
    const parrot = bitmapGrid(PARROT);

    // A stroke moves exactly one terminal cell and only ever adds or recolors
    // a pixel, never erases one, so the silhouette stays solid, no gap opens.
    if (phase >= Flap.REST_TICKS) {
      if (up) {
        parrot[0][0] = Flap.WING; // the wing lifted clear of the back
        parrot[1][0] = Flap.WING;
      } else {
        parrot[4][1] = Flap.WING; // the wing swept under the belly
        parrot[5][1] = Flap.WING;
      }
    }

    const bird = poseGrid();
    placeGrid(bird, parrot, up ? Flap.FLOAT_DROP_PX : 0, 0);
    return birdCanvas(bird);
  }
}

/**
 * The nod: the head dips half a cell and lifts again while the body holds.
 *
 * The head covers the body pixels it lands on, which is what a dip looks like,
 * and the crown it vacates opens no hole because nothing else sits above the
 * head.
 */
class Nod extends BrandMotion {
  private static readonly PERIOD_TICKS = 9;
  private static readonly LIFT_TICKS = 6;
  private static readonly DIP_PX = 1;

  pose(tick: number): Grid {
    const grid = restingPose();
    if (tick % Nod.PERIOD_TICKS < Nod.LIFT_TICKS) return birdCanvas(grid);

    const head = HEAD_PIXELS.map(([row, col]) => grid[row][col]);
    for (const [row, col] of HEAD_PIXELS) grid[row][col] = null;

    HEAD_PIXELS.forEach(([row, col], index) => {
      grid[row + Nod.DIP_PX][col] = head[index];
    });
    return birdCanvas(grid);
  }
}

/**
 * The look-around: the head mirrors to glance back over the shoulder, then
 * turns forward again, while the body and tail hold still.
 *
 * The beak's black lower half lands on the wing's top pixel, and the vacated
 * right column simply empties, so the head reads as turned rather than moved.
 */
class LookAround extends BrandMotion {
  private static readonly PERIOD_TICKS = 20;
  private static readonly FORWARD_TICKS = 16;

  pose(tick: number): Grid {
    const grid = restingPose();
    if (tick % LookAround.PERIOD_TICKS < LookAround.FORWARD_TICKS) {
      return birdCanvas(grid);
    }

    const head = HEAD_PIXELS.map(([row, col]) => grid[row][col]);
    for (const [row, col] of HEAD_PIXELS) grid[row][col] = null;

    HEAD_PIXELS.forEach(([row, col], index) => {
      grid[row][PARROT[0].length - 1 - col] = head[index];
    });
    return birdCanvas(grid);
  }
}

/**
 * The song: the beak opens and closes on a slow warble while the body holds.
 *
 * The beak is a white upper mandible over a black lower one, so an open beak
 * drops the black one a pixel and leaves the background showing between them.
 * That mouth is the one interior gap a pose may open, and it opens down a
 * column, so every row of the bird still stays one unbroken run.
 */
class Sing extends BrandMotion {
  private static readonly PERIOD_TICKS = 12;
  private static readonly REST_TICKS = 2;
  /** Two beats per cycle, each open for its first ticks and shut after. */
  private static readonly BEAT_TICKS = 6;
  private static readonly OPEN_TICKS = 4;
  /** The lower mandible's row, in parrot pixel rows like its neighbours. */
  private static readonly BEAK_ROW = 2;
  /** The music glyphs it sings, in the order it lets them go. */
  private static readonly NOTES = ["🎵", "🎶", "🎼"] as const;
  /** Ticks between two notes, and columns a note gains per tick. */
  private static readonly NOTE_EMIT_TICKS = 3;
  private static readonly NOTE_COLUMNS_PER_TICK = 2;
  /** Ticks a note takes to climb one header row. */
  private static readonly NOTE_RISE_TICKS = 4;
  /**
   * Where a note leaves, in header rows and columns rather than parrot pixels:
   * the mouth's row, one column past the beak.
   */
  private static readonly NOTE_HEADER_ROW = 1;
  private static readonly NOTE_COLUMN = PARROT[0].length;

  pose(tick: number): Grid {
    const grid = restingPose();
    const phase = tick % Sing.PERIOD_TICKS;
    if (phase < Sing.REST_TICKS) return birdCanvas(grid);

    const beatTick = (phase - Sing.REST_TICKS) % Sing.BEAT_TICKS;
    if (beatTick >= Sing.OPEN_TICKS) return birdCanvas(grid);

    const beakCol = PARROT[0].length - 1;
    const lowerBeak = grid[Sing.BEAK_ROW][beakCol];
    grid[Sing.BEAK_ROW][beakCol] = null;
    grid[Sing.BEAK_ROW + 1][beakCol] = lowerBeak;
    return birdCanvas(grid);
  }

  /**
   * The song: a glyph leaves the mouth every NOTE_EMIT_TICKS.
   *
   * A note keeps drifting forward and climbing, a row every NOTE_RISE_TICKS,
   * and disappears the moment it goes over the top of the terminal or past the
   * right edge of the header, rather than be cut in half or hang there.
   *
   * @param tick - Ticks into the motion, the clock pose() runs on.
   * @param width - Header width in columns, the right boundary.
   * @returns The notes still on screen, oldest first.
   */
  notes(tick: number, width: number): HeaderGlyph[] {
    const newest = tick - (tick % Sing.NOTE_EMIT_TICKS);
    const notes: HeaderGlyph[] = [];

    // Walk back through the births: every older note is further right and
    // higher, so the first one out of the terminal ends the walk.
    for (let born = newest; born >= 0; born -= Sing.NOTE_EMIT_TICKS) {
      const age = tick - born;
      const row = Sing.NOTE_HEADER_ROW - Math.floor(age / Sing.NOTE_RISE_TICKS);
      if (row < 0) break;

      const glyph =
        Sing.NOTES[(born / Sing.NOTE_EMIT_TICKS) % Sing.NOTES.length];
      const col = Sing.NOTE_COLUMN + age * Sing.NOTE_COLUMNS_PER_TICK;
      if (col + visibleWidth(glyph) > width) break;

      notes.push({ row, col, glyph });
    }

    return notes.reverse();
  }
}

/** The motions a session picks one of at random, so greetings differ. */
export const MOTIONS: readonly Motion[] = [
  new Flap(),
  new Nod(),
  new LookAround(),
  new Sing(),
];

export type Phase = "logo" | "intro" | "loop" | "outro";

export interface Frame {
  readonly phase: Phase;
  readonly grid: Grid;
}

/** Ticks of intro played `elapsedMs` in, once the logo's delay is over. */
function introTickAt(elapsedMs: number): number {
  return Math.floor((elapsedMs - LOGO_DELAY_MS) / FRAME_INTERVAL_MS);
}

/** Ticks of loop played `elapsedMs` in, once the intro has handed over. */
function loopTickAt(elapsedMs: number): number {
  return Math.floor((elapsedMs - ANIMATION_START_MS) / FRAME_INTERVAL_MS);
}

/**
 * Morph step on screen `elapsedMs` in: 0 while the logo still stands, 1 through
 * INTRO_TICKS while the intro recomposes it, the parrot from then on.
 */
function shownStep(elapsedMs: number): number {
  return Math.min(INTRO_TICKS, introTickAt(elapsedMs) + 1);
}

/**
 * Ticks the outro still has to play, `elapsedMs` after the first message: it
 * flies home from the step on screen when that message ends, so a message
 * under the logo calls for none at all.
 */
function outroTicksLeft(elapsedMs: number, outroAtMs: number): number {
  const played = Math.floor((elapsedMs - outroAtMs) / FRAME_INTERVAL_MS);
  return shownStep(outroAtMs) - played;
}

/**
 * Build the frame shown `elapsedMs` after the session started.
 *
 * The greeting runs the motion's own three stretches: its intro recomposing
 * the logo, then its loop, then, once the conversation holds a message, its
 * outro flying the parrot home, after which the Pi logo stands for good.
 *
 * @param elapsedMs - Time since session_start.
 * @param motion - The motion this session picked.
 * @param outroAtMs - Time since session_start when the conversation's first
 *   message ended, or undefined while the parrot is still welcome.
 * @returns The phase and its canvas.
 */
export function frameFor(
  elapsedMs: number,
  motion: Motion,
  outroAtMs?: number,
): Frame {
  if (outroAtMs !== undefined) {
    const left = outroTicksLeft(elapsedMs, outroAtMs);
    if (left <= 0) return { phase: "logo", grid: logoCanvas() };
    return { phase: "outro", grid: motion.end(INTRO_TICKS - left) };
  }

  if (elapsedMs < LOGO_DELAY_MS) {
    return { phase: "logo", grid: logoCanvas() };
  }

  if (elapsedMs < ANIMATION_START_MS) {
    return { phase: "intro", grid: motion.start(introTickAt(elapsedMs)) };
  }

  return { phase: "loop", grid: motion.pose(loopTickAt(elapsedMs)) };
}

function foreground(color: Rgb, mode: TerminalColorMode): string {
  return foregroundAnsi(rgbColor(color[0], color[1], color[2]), mode);
}

function background(color: Rgb, mode: TerminalColorMode): string {
  return backgroundAnsi(rgbColor(color[0], color[1], color[2]), mode);
}

function sameColor(first: Rgb, second: Rgb): boolean {
  return (
    first[0] === second[0] && first[1] === second[1] && first[2] === second[2]
  );
}

/** Render two stacked pixels into one terminal cell, resetting after each. */
function renderCell(
  top: Rgb | null,
  bottom: Rgb | null,
  mode: TerminalColorMode,
): string {
  if (top === null) {
    return bottom === null
      ? " "
      : `${foreground(bottom, mode)}${LOWER_HALF_BLOCK}${RESET}`;
  }
  if (bottom === null) {
    return `${foreground(top, mode)}${UPPER_HALF_BLOCK}${RESET}`;
  }
  if (sameColor(top, bottom)) {
    return `${foreground(top, mode)}${FULL_BLOCK}${RESET}`;
  }
  return `${foreground(top, mode)}${background(bottom, mode)}${UPPER_HALF_BLOCK}${RESET}`;
}

/**
 * Render a pixel canvas as terminal lines.
 *
 * @param grid - Canvas with an even number of pixel rows.
 * @param mode - Terminal color mode, so brand colors follow the terminal.
 * @returns One ANSI-styled line per pixel row pair, each fixed at
 *   CANVAS_WIDTH_PX visible columns.
 */
export function renderCanvas(grid: Grid, mode: TerminalColorMode): string[] {
  const lines: string[] = [];

  for (let row = 0; row < grid.length; row += 2) {
    let line = "";
    for (let col = 0; col < CANVAS_WIDTH_PX; col++) {
      line += renderCell(grid[row][col], grid[row + 1][col], mode);
    }
    lines.push(line);
  }

  return lines;
}

/**
 * True when the session already holds a conversation. The greeting belongs to
 * a fresh start, so a resumed, forked, or reloaded session with messages keeps
 * Pi's built-in header, while a reloaded but still empty one gets the parrot.
 */
function hasConversation(ctx: ExtensionContext): boolean {
  return ctx.sessionManager
    .getEntries()
    .some((entry) => entry.type === "message");
}

/** Shared frame clock and header lifecycle for one extension instance. */
class ParrotAnimation {
  /** Elapsed ms of the first message; undefined while the bird plays. */
  private outroAtMs: number | undefined;

  /** The motion this session picked at random in start(). */
  private motion: Motion = MOTIONS[0];

  private startedAt = 0;
  private timer: ReturnType<typeof setInterval> | undefined;
  private startTimer: ReturnType<typeof setTimeout> | undefined;
  private header: ParrotHeader | undefined;

  /**
   * Start the greeting in a TUI session, without leaving a previous session's
   * clock alive.
   */
  start(ctx: ExtensionContext): void {
    this.stop();

    this.startedAt = Date.now();
    this.outroAtMs = undefined;
    this.motion = MOTIONS[Math.floor(Math.random() * MOTIONS.length)];
    ctx.ui.setHeader((tui, theme) => {
      this.header = new ParrotHeader(tui, theme, this);
      return this.header;
    });
    // The opening logo does not change, so the frame clock only starts when its
    // first pixel is due to move.
    this.startTimer = setTimeout(() => this.beginClock(), LOGO_DELAY_MS);
  }

  /** Run the frame clock while pixels change, and stop it once they do not. */
  private beginClock(): void {
    this.startTimer = undefined;
    if (this.settled()) {
      this.stop();
      return;
    }

    this.header?.requestRender();
    this.timer = setInterval(() => {
      this.header?.requestRender();
      // The logo is the last frame and never changes, so the clock can stop.
      if (this.settled()) this.stop();
    }, FRAME_INTERVAL_MS);
  }

  /** Send the parrot back into the Pi logo, once per session. */
  beginOutro(): void {
    if (this.outroAtMs !== undefined) return;
    this.outroAtMs = this.elapsedMs();
  }

  /** Time since this animation's session started. */
  private elapsedMs(): number {
    return Date.now() - this.startedAt;
  }

  /**
   * Draw the greeting over the header's text rows: the bird's pixels first,
   * then any glyphs in front of them. The header owns the text and its layout,
   * the animation owns every layer drawn on top of it.
   *
   * @param rows - The wrapped, themed header rows.
   * @param width - Width in columns of the rows, and the glyphs' boundary.
   * @param mode - Terminal color mode, so brand colors follow the terminal.
   * @returns The rows with the greeting drawn over them.
   */
  paint(
    rows: readonly string[],
    width: number,
    mode: TerminalColorMode,
  ): string[] {
    // One clock reading per frame, so every layer draws the same instant.
    const elapsedMs = this.elapsedMs();
    const frame = frameFor(elapsedMs, this.motion, this.outroAtMs);
    const canvas = renderCanvas(frame.grid, mode);
    const glyphs = this.glyphs(elapsedMs, width);

    return rows.map((row, index) => {
      const line =
        index < canvas.length
          ? ParrotAnimation.pixelsOverText(canvas[index], row)
          : row;
      return ParrotAnimation.glyphsOverText(line, glyphs, index, width);
    });
  }

  /**
   * Draw one brand-cell row of animation pixels over an already wrapped header
   * row: the bird wins, the text keeps its column.
   *
   * @param canvasLine - Rendered canvas row pair, CANVAS_WIDTH_PX columns wide.
   * @param text - The wrapped row, already themed and placed.
   * @returns The composited row, at least as wide as either input.
   */
  private static pixelsOverText(canvasLine: string, text: string): string {
    const totalWidth = Math.max(visibleWidth(canvasLine), visibleWidth(text));
    let line = text;

    for (let column = 0; column < visibleWidth(canvasLine); column++) {
      const pixel = sliceByColumn(canvasLine, column, 1, true);
      if (!PAINTED_CELL.test(pixel)) continue;
      line = compositeTuiLine(line, pixel, column, 1, totalWidth);
    }

    return line;
  }

  /**
   * Draw one row's glyphs in front of an already composited row: a glyph covers
   * the cells it lands on, letters included, and the text returns once it has
   * moved on, so the row never shifts.
   *
   * @param line - The row, already themed and composited with the bird.
   * @param glyphs - Every glyph in front of the header, in any row.
   * @param row - The header row being drawn.
   * @param width - The row's full width; a glyph may fly out past the end of its
   *   text, which is trimmed of trailing spaces.
   * @returns The row with the glyphs it carries drawn on it.
   */
  private static glyphsOverText(
    line: string,
    glyphs: readonly HeaderGlyph[],
    row: number,
    width: number,
  ): string {
    let drawn = line;

    for (const glyph of glyphs) {
      if (glyph.row !== row) continue;
      const glyphWidth = visibleWidth(glyph.glyph);
      drawn = compositeTuiLine(
        drawn,
        glyph.glyph,
        glyph.col,
        glyphWidth,
        width,
      );
    }

    return drawn;
  }

  /**
   * Glyphs the picked motion sends over the header's text; the silent motions
   * send none.
   *
   * @param elapsedMs - Time since session_start, so every layer agrees.
   * @param width - Header width in columns, the right boundary.
   * @returns The glyphs still in front of the text, empty until the intro
   *   hands over and again once the conversation starts.
   */
  private glyphs(elapsedMs: number, width: number): HeaderGlyph[] {
    if (!(this.motion instanceof Sing)) return [];
    if (this.outroAtMs !== undefined) return [];
    if (elapsedMs < ANIMATION_START_MS) return [];
    return this.motion.notes(loopTickAt(elapsedMs), width);
  }

  /** True once the outro has landed on the logo for good. */
  private settled(): boolean {
    if (this.outroAtMs === undefined) return false;
    return outroTicksLeft(this.elapsedMs(), this.outroAtMs) <= 0;
  }

  /** Stop the frame clock; safe to call more than once. */
  stop(): void {
    if (this.startTimer !== undefined) {
      clearTimeout(this.startTimer);
      this.startTimer = undefined;
    }
    if (this.timer === undefined) return;
    clearInterval(this.timer);
    this.timer = undefined;
  }
}

/** Compact startup instructions, formatted with Pi's configured keybindings. */
function compactInstructions(theme: Theme): string {
  const hint = (key: string, description: string) =>
    theme.fg("dim", key) + theme.fg("muted", ` ${description}`);
  return [
    hint(keyText("app.interrupt"), "interrupt"),
    hint(`${keyText("app.clear")}/${keyText("app.exit")}`, "clear/exit"),
    hint("/", "commands"),
    hint("!", "bash"),
    hint(keyText("app.tools.expand"), "more"),
  ].join(theme.fg("muted", " · "));
}

/** Collapsed onboarding line shown by Pi's built-in startup header. */
function compactOnboarding(): string {
  return `Press ${keyText("app.tools.expand")} to show full startup help and loaded resources.`;
}

/**
 * Closing hint of Pi's built-in startup header, below a blank line. Pi builds
 * it inside its interactive mode and does not export it, so the wording is
 * repeated here to keep the custom header identical to the built-in one.
 */
function piOnboarding(): string {
  return "Pi can explain its own features and look up its docs. Ask it how to use or extend Pi.";
}

/** Custom header component: Pi's startup text, with the greeting drawn over
 * it. */
class ParrotHeader implements Component {
  private readonly tui: TUI;
  private readonly theme: Theme;
  private readonly animation: ParrotAnimation;

  constructor(tui: TUI, theme: Theme, animation: ParrotAnimation) {
    this.tui = tui;
    this.theme = theme;
    this.animation = animation;
  }

  requestRender(): void {
    this.tui.requestRender();
  }

  /**
   * Render Pi's startup header with the greeting drawn over it.
   *
   * @param width - Terminal columns this header may occupy.
   * @returns The header lines, each within `width` columns.
   */
  render(width: number): string[] {
    const version = this.theme.fg("dim", `v${VERSION}`);
    const hints = compactInstructions(this.theme);
    const onboarding = this.theme.fg("dim", compactOnboarding());
    const closing = this.theme.fg("dim", piOnboarding());

    // Pi's built-in header is a Text with a one-column margin that shrinks on
    // very narrow terminals; match it so both headers align and wrap alike.
    const paddingX = Math.min(
      HEADER_PADDING_X,
      Math.max(0, Math.floor((width - 1) / 2)),
    );
    const contentWidth = Math.max(1, width - paddingX * 2);

    // Wrap the same block Pi's header wraps, brand cell left as blank space so
    // the text beside it keeps its column, then let the animation draw over
    // the first rows: it stays in one piece while the text wraps at Pi's own
    // width.
    const beside = " ".repeat(BRAND_TEXT_COLUMN);
    const rows = wrapTextWithAnsi(
      [beside + version, beside + hints, onboarding, "", closing].join("\n"),
      contentWidth,
    );

    const drawn = this.animation.paint(
      rows,
      contentWidth,
      this.theme.getColorMode(),
    );
    const indent = " ".repeat(paddingX);
    return drawn.map((row) => indent + truncateToWidth(row, contentWidth, ""));
  }

  invalidate(): void {
    // Frames derive from elapsed time, so there is no cached state to drop.
  }

  dispose(): void {
    this.animation.stop();
  }
}

/**
 * Register the parrot greeting: a fresh TUI session gets the animated header,
 * while a session that already holds a conversation keeps Pi's own header.
 *
 * @param pi - Extension API used to hook the session lifecycle.
 */
export default function parrot(pi: ExtensionAPI): void {
  const animation = new ParrotAnimation();

  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;

    // Pi carries a custom header across sessions, so one that is already under
    // way has to get the built-in header back instead of a greeting.
    if (hasConversation(ctx)) {
      animation.stop();
      ctx.ui.setHeader(undefined);
      return;
    }

    animation.start(ctx);
  });

  // The greeting belongs to an empty session, so the first message it holds
  // sends the bird home.
  pi.on("message_end", () => animation.beginOutro());
  pi.on("session_shutdown", () => animation.stop());
}
