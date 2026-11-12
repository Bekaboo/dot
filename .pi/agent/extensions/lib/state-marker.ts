/**
 * One vocabulary for the state markers of the background-work overlays.
 *
 * `/subagents` and `/timers` list jobs that run, finish, fail, or run out of
 * time, and a reader moves between the two views, so the same state has to look
 * the same in both: the same spinner while a job runs, and the same glyph and
 * color once it ends. Duplicating the tables per extension let the two drift,
 * so they live here and each extension imports them.
 *
 * Only the parts both extensions use are exported: the state type, the marker
 * renderer, and the spinner cadence. Anything an extension needs on its own,
 * such as its row layout, stays there.
 */

import type { Theme } from "@earendil-works/pi-coding-agent";

/** Braille frames pi's built-in working spinner uses. */
export const SPINNER_FRAMES = [
  "⠋",
  "⠙",
  "⠹",
  "⠸",
  "⠼",
  "⠴",
  "⠦",
  "⠧",
  "⠇",
  "⠏",
];

/** Spinner frame interval in ms, matching pi's built-in working indicator. */
export const SPINNER_INTERVAL_MS = 80;

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
 * Glyph and color for a job's state, with the spinner while it runs.
 *
 * Callers draw this right after the id column, so the markers line up as one
 * column of their own.
 *
 * @param state - State of the job.
 * @param frame - Current spinner frame index.
 * @param theme - Active theme.
 * @returns The styled marker.
 */
export function stateMarker(
  state: RunState,
  frame: number,
  theme: Theme,
): string {
  if (state === "running") {
    return theme.fg(
      STATE_COLOR.running,
      SPINNER_FRAMES[frame % SPINNER_FRAMES.length],
    );
  }
  return theme.fg(STATE_COLOR[state], STATE_GLYPH[state]);
}
