/**
 * Spinner and state markers shared by the background-work overlays.
 *
 * `/subagents` and `/timers` list jobs that run, finish, fail, or run out of
 * time, and a reader moves between the two views, so the same state has to look
 * the same in both: the same spinner while a job runs, and the same glyph and
 * color once it ends. The spinner also owns its animation, so neither overlay
 * keeps its own interval bookkeeping.
 *
 * pi-tui's `Loader` draws the same braille frames, but as a whole line with its
 * own message; these overlays need the spinner as one cell of a table row.
 */

import type { Theme } from "@earendil-works/pi-coding-agent";

/** Braille frames pi's built-in working spinner uses. */
const SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

/** Spinner frame interval in ms, matching pi's built-in working indicator. */
const SPINNER_INTERVAL_MS = 80;

/**
 * Display color for each run state; the single source of truth.
 *
 * `timeout` is a failure of patience rather than of the work, so it stays a
 * warning instead of an error.
 */
const STATE_COLOR = {
  running: "accent",
  done: "success",
  failed: "error",
  timeout: "warning",
  killed: "dim",
} as const;

/** How a background job can end, or `running` while it has not. */
export type RunState = keyof typeof STATE_COLOR;

/** Glyph for each finished state; a running job shows the spinner instead. */
const STATE_GLYPH = {
  done: "✓",
  failed: "✗",
  timeout: "⧖",
  killed: "·",
} as const;

/**
 * Animated state marker for one overlay.
 *
 * The overlay calls `sync()` whenever its rows may have changed and `stop()`
 * when it closes; the spinner advances only while some job is running, and
 * asks for a render on every frame.
 */
export class Spinner {
  private frame = 0;
  private interval: ReturnType<typeof setInterval> | undefined;
  private readonly requestRender: () => void;

  /**
   * @param requestRender - Redraws the overlay after each frame.
   */
  constructor(requestRender: () => void) {
    this.requestRender = requestRender;
  }

  /**
   * Run the animation while some job runs, and stop it otherwise.
   *
   * @param running - Whether any row of the overlay is still running.
   */
  sync(running: boolean): void {
    if (!running) {
      this.stop();
      return;
    }
    if (this.interval) return;
    this.interval = setInterval(() => {
      this.frame = (this.frame + 1) % SPINNER_FRAMES.length;
      this.requestRender();
    }, SPINNER_INTERVAL_MS);
  }

  /** Stop the animation, e.g. once the overlay is closed. */
  stop(): void {
    if (!this.interval) return;
    clearInterval(this.interval);
    this.interval = undefined;
  }

  /**
   * Glyph and color for a job's state, with the current frame while it runs.
   *
   * Callers draw this right after the id column, so the markers line up as one
   * column of their own.
   *
   * @param state - State of the job.
   * @param theme - Active theme.
   * @returns The styled marker.
   */
  marker(state: RunState, theme: Theme): string {
    if (state === "running") {
      return theme.fg(STATE_COLOR.running, SPINNER_FRAMES[this.frame]);
    }
    return theme.fg(STATE_COLOR[state], STATE_GLYPH[state]);
  }
}
