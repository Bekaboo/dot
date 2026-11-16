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

type PixelColor = keyof typeof PALETTE;
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
export const MORPH_STEPS = 10;
export const CANVAS_WIDTH_PX = 16;
/** Four terminal rows: the bird's three, plus one for it to float down into. */
export const CANVAS_HEIGHT_PX = 8;

/**
 * Canvas position of the resting parrot's top-left pixel: it lands on the same
 * brand cell the logo occupied, so the morph recomposes in place.
 */
export const PARROT_TOP = 0;
export const PARROT_LEFT = 0;

const MORPH_MS = MORPH_STEPS * FRAME_INTERVAL_MS;
export const ANIMATION_START_MS = LOGO_DELAY_MS + MORPH_MS;

/**
 * A looping pose sequence the parrot plays once the morph hands over.
 *
 * A motion owns its own timing and pixels. `start()` is the first tick of a
 * cycle at which the bird may leave the resting parrot, which is what lets the
 * morph's last frame and the motion's first frames agree; `end()` is the tick
 * at which the cycle completes and repeats.
 */
export interface Motion {
  start(): number;
  end(): number;
  /** The posed pixels for a tick within one cycle, on a canvas-tall grid. */
  pose(tick: number): Grid;
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
  return PALETTE[char as PixelColor];
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

type BitmapPixel = {
  readonly row: number;
  readonly col: number;
  readonly color: Rgb;
};

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
 * Some parrot pixels share a source pixel: the logo has 10 colored pixels and
 * the parrot 15, so the extra ones grow out of the nearest matching color.
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
 * @param step - Morph step, 1 through MORPH_STEPS.
 * @returns The canvas at `step / MORPH_STEPS` progress; the last step is the
 *   exact resting parrot.
 */
function morphCanvas(step: number): Grid {
  const progress = step / MORPH_STEPS;
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

/**
 * The wing flap: one azure cell rises above the back, then sweeps under the
 * belly, while the body floats a cell down on the upstroke.
 */
class Flap implements Motion {
  private static readonly PERIOD_TICKS = 12;
  private static readonly REST_TICKS = 2;
  private static readonly UPSTROKE_TICKS = 5;
  private static readonly FLOAT_DROP_PX = 2;
  /** The wing's azure, against the Pi blue tail it folds above. */
  private static readonly WING = PALETTE.A;

  start(): number {
    return Flap.REST_TICKS;
  }

  end(): number {
    return Flap.PERIOD_TICKS;
  }

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

    const grid = poseGrid();
    placeGrid(grid, parrot, up ? Flap.FLOAT_DROP_PX : 0, 0);
    return grid;
  }
}

/**
 * The nod: the head dips half a cell and lifts again while the body holds.
 *
 * The head covers the body pixels it lands on, which is what a dip looks like,
 * and the crown it vacates opens no hole because nothing else sits above the
 * head.
 */
class Nod implements Motion {
  private static readonly PERIOD_TICKS = 9;
  private static readonly LIFT_TICKS = 6;
  private static readonly DIP_PX = 1;

  start(): number {
    return Nod.LIFT_TICKS;
  }

  end(): number {
    return Nod.PERIOD_TICKS;
  }

  pose(tick: number): Grid {
    const grid = restingPose();
    if (tick % Nod.PERIOD_TICKS < Nod.LIFT_TICKS) return grid;

    const head = HEAD_PIXELS.map(([row, col]) => grid[row][col]);
    for (const [row, col] of HEAD_PIXELS) grid[row][col] = null;

    HEAD_PIXELS.forEach(([row, col], index) => {
      grid[row + Nod.DIP_PX][col] = head[index];
    });
    return grid;
  }
}

/**
 * The look-around: the head mirrors to glance back over the shoulder, then
 * turns forward again, while the body and tail hold still.
 *
 * The beak's black lower half lands on the wing's top pixel, and the vacated
 * right column simply empties, so the head reads as turned rather than moved.
 */
class LookAround implements Motion {
  private static readonly PERIOD_TICKS = 20;
  private static readonly FORWARD_TICKS = 16;

  start(): number {
    return LookAround.FORWARD_TICKS;
  }

  end(): number {
    return LookAround.PERIOD_TICKS;
  }

  pose(tick: number): Grid {
    const grid = restingPose();
    if (tick % LookAround.PERIOD_TICKS < LookAround.FORWARD_TICKS) return grid;

    const head = HEAD_PIXELS.map(([row, col]) => grid[row][col]);
    for (const [row, col] of HEAD_PIXELS) grid[row][col] = null;

    HEAD_PIXELS.forEach(([row, col], index) => {
      grid[row][PARROT[0].length - 1 - col] = head[index];
    });
    return grid;
  }
}

/** The motions a session picks one of at random, so greetings differ. */
export const MOTIONS: readonly Motion[] = [
  new Flap(),
  new Nod(),
  new LookAround(),
];

export type Phase = "logo" | "morph" | "animate" | "shatter";

export interface Frame {
  readonly phase: Phase;
  readonly grid: Grid;
}

/** Morph step the pixels have reached `elapsedMs` in, 0 through MORPH_STEPS. */
function morphStepAt(elapsedMs: number): number {
  if (elapsedMs < LOGO_DELAY_MS) return 0;
  if (elapsedMs >= ANIMATION_START_MS) return MORPH_STEPS;
  return Math.min(
    MORPH_STEPS,
    Math.floor((elapsedMs - LOGO_DELAY_MS) / FRAME_INTERVAL_MS) + 1,
  );
}

/**
 * Fly the pixels back into the Pi logo: the morph played backwards from the
 * step it had reached when the user typed, then the logo for good.
 *
 * @param elapsedMs - Time since session_start.
 * @param shatterAtMs - Time since session_start when the user first typed.
 */
function shatterFrame(elapsedMs: number, shatterAtMs: number): Frame {
  const flown = Math.floor((elapsedMs - shatterAtMs) / FRAME_INTERVAL_MS);
  const step = morphStepAt(shatterAtMs) - flown;
  if (step <= 0) return { phase: "logo", grid: logoCanvas() };
  return { phase: "shatter", grid: morphCanvas(step) };
}

/**
 * Build the frame shown `elapsedMs` after the session started.
 *
 * @param elapsedMs - Time since session_start.
 * @param motion - The motion this session picked.
 * @param shatterAtMs - Time since session_start when the user first typed, or
 *   undefined while the parrot is still welcome.
 * @returns The phase and its pixel grid.
 */
export function frameFor(
  elapsedMs: number,
  motion: Motion,
  shatterAtMs?: number,
): Frame {
  if (shatterAtMs !== undefined) return shatterFrame(elapsedMs, shatterAtMs);

  if (elapsedMs < LOGO_DELAY_MS) {
    return { phase: "logo", grid: logoCanvas() };
  }

  if (elapsedMs < ANIMATION_START_MS) {
    return { phase: "morph", grid: morphCanvas(morphStepAt(elapsedMs)) };
  }

  const tick = Math.floor((elapsedMs - ANIMATION_START_MS) / FRAME_INTERVAL_MS);
  const canvas = emptyCanvas();
  placeGrid(canvas, motion.pose(tick), PARROT_TOP, PARROT_LEFT);
  return { phase: "animate", grid: canvas };
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

const FIRST_PRINTABLE_CODE = 0x20;
const DELETE_CHARACTER = "\x7f";

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

/**
 * True when raw terminal input carries a typed character. Escape sequences
 * (arrows, mouse, bracketed paste) and lone control bytes are not typing, so
 * scrolling or interrupting does not end the greeting.
 */
function isTyping(data: string): boolean {
  if (data.startsWith("\x1b")) return false;
  return [...data].some(
    (char) =>
      char.charCodeAt(0) >= FIRST_PRINTABLE_CODE && char !== DELETE_CHARACTER,
  );
}

/** Shared frame clock and header lifecycle for one extension instance. */
class ParrotAnimation {
  /** Elapsed ms of the first typed character; undefined while the bird plays. */
  shatterAt: number | undefined;

  /** The motion this session picked at random in start(). */
  motion: Motion = MOTIONS[0];

  private startedAt = 0;
  private shatterSteps = 0;
  private timer: ReturnType<typeof setInterval> | undefined;
  private startTimer: ReturnType<typeof setTimeout> | undefined;
  private unsubscribe: (() => void) | undefined;
  private header: ParrotHeader | undefined;

  /**
   * Start the greeting in a TUI session, without leaving a previous session's
   * clock or input listener alive.
   */
  start(ctx: ExtensionContext): void {
    this.stop();

    this.startedAt = Date.now();
    this.shatterAt = undefined;
    this.shatterSteps = 0;
    this.motion = MOTIONS[Math.floor(Math.random() * MOTIONS.length)];
    ctx.ui.setHeader((tui, theme) => {
      this.header = new ParrotHeader(tui, theme, this);
      return this.header;
    });
    this.unsubscribe = ctx.ui.onTerminalInput((data) => {
      if (isTyping(data)) this.beginShatter();
      return undefined;
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

  /** Send the parrot back to the Pi logo, once per session. */
  beginShatter(): void {
    if (this.shatterAt !== undefined) return;
    this.shatterAt = this.elapsedMs();
    this.shatterSteps = morphStepAt(this.shatterAt);
  }

  /** Time since this animation's session started. */
  elapsedMs(): number {
    return Date.now() - this.startedAt;
  }

  /** True once the shatter has landed on the logo for good. */
  private settled(): boolean {
    if (this.shatterAt === undefined) return false;
    return (
      this.elapsedMs() - this.shatterAt >= this.shatterSteps * FRAME_INTERVAL_MS
    );
  }

  /** Stop the frame clock and input listener; safe to call more than once. */
  stop(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
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

/**
 * Draw one brand-cell row of animation pixels over an already wrapped header
 * line: the bird wins, the text keeps its column.
 *
 * @param canvasLine - Rendered canvas row pair, CANVAS_WIDTH_PX columns wide.
 * @param text - The wrapped line, already themed and placed.
 * @returns The composited line, at least as wide as either input.
 */
function withAnimationOverText(canvasLine: string, text: string): string {
  const totalWidth = Math.max(visibleWidth(canvasLine), visibleWidth(text));
  let line = text;

  for (let column = 0; column < visibleWidth(canvasLine); column++) {
    const pixel = sliceByColumn(canvasLine, column, 1, true);
    if (!PAINTED_CELL.test(pixel)) continue;
    line = compositeTuiLine(line, pixel, column, 1, totalWidth);
  }

  return line;
}

/** Custom header component: the animated brand cell and Pi's startup text. */
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

  render(width: number): string[] {
    const frame = frameFor(
      this.animation.elapsedMs(),
      this.animation.motion,
      this.animation.shatterAt,
    );
    const canvas = renderCanvas(frame.grid, this.theme.getColorMode());
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
    // the text beside it keeps its column, then draw the bird over the first
    // rows: it stays in one piece while the text wraps at Pi's own width.
    const beside = " ".repeat(BRAND_TEXT_COLUMN);
    const rows = wrapTextWithAnsi(
      [beside + version, beside + hints, onboarding, "", closing].join("\n"),
      contentWidth,
    );

    const indent = " ".repeat(paddingX);
    return rows.map((row, index) => {
      const line =
        index < canvas.length ? withAnimationOverText(canvas[index], row) : row;
      return indent + truncateToWidth(line, contentWidth, "");
    });
  }

  invalidate(): void {
    // Frames derive from elapsed time, so there is no cached state to drop.
  }

  dispose(): void {
    this.animation.stop();
  }
}

export default function parrot(pi: ExtensionAPI) {
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

  pi.on("session_shutdown", () => animation.stop());
}
