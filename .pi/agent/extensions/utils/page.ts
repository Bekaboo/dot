/**
 * Height helpers shared by the full-page overlays.
 *
 * `/subagents`, `/timers` and `/todos` all replace pi's editor slot with a
 * bordered page. Pi lays that slot out inside the dock under the transcript, so
 * a page taller than the terminal loses its last rows: the Escape hint and the
 * bottom border. These helpers size a page body to the rows the terminal leaves,
 * move a window of rows, and say which rows it hides.
 */

import type { Theme } from "@earendil-works/pi-coding-agent";
import { truncateToWidth } from "@earendil-works/pi-tui";

/**
 * Rows pi keeps for itself around a custom component: the transcript line above
 * it, the status line, and the two-line footer of a session with an extension
 * footer.
 */
export const VIEWPORT_RESERVE_ROWS = 4;

/** Horizontal padding each page adds inside its border. */
export const PAGE_PADDING_X = 2;

/**
 * Rows a page body may fill at this width.
 *
 * The caller empties the body and sets the summary and the hint first, so the
 * measured chrome matches the final frame.
 *
 * @param renderChrome - Renders the page with an empty body and its hint set.
 * @param terminalRows - Terminal height the page renders into.
 * @param gapRows - Rows the blank line between the body and the content above it
 *   takes. It is not part of the measured chrome while the body is empty, and 0
 *   when that content already draws the gap itself.
 * @returns Lines left for the body, or 0 when only the chrome fits.
 */
export function bodyRows(
  renderChrome: () => number,
  terminalRows: number,
  gapRows = 1,
): number {
  const budget = Math.max(0, terminalRows - VIEWPORT_RESERVE_ROWS);
  return Math.max(0, budget - renderChrome() - gapRows);
}

/**
 * Dim a page hint and keep it on one line, so it never grows the box.
 *
 * @param theme - Active theme.
 * @param text - Hint text.
 * @param width - Page width, including the text padding.
 * @returns The styled, width-truncated hint.
 */
export function hintLine(theme: Theme, text: string, width: number): string {
  const inner = Math.max(1, width - PAGE_PADDING_X * 2);
  return theme.fg("dim", truncateToWidth(text, inner, "...", true));
}

/**
 * Describe the rows a window hides, so the hint says more rows exist.
 *
 * @param start - Index of the window's first row.
 * @param shown - Rows the window shows.
 * @param total - Number of rows there are.
 * @returns Suffix such as "  (5-12 of 20)", empty when nothing is hidden.
 */
export function windowLabel(
  start: number,
  shown: number,
  total: number,
): string {
  if (shown >= total) return "";
  if (shown === 0) return `  (${total} hidden)`;
  return `  (${start + 1}-${start + shown} of ${total})`;
}

/**
 * Index of the first row of a window that keeps one row selected.
 *
 * @param selected - Index of the selected row within all rows.
 * @param total - Number of rows there are.
 * @param capacity - Rows the window holds.
 * @returns Index of the window's first row.
 */
export function windowStart(
  selected: number,
  total: number,
  capacity: number,
): number {
  const last = Math.max(0, total - capacity);
  return Math.min(last, Math.max(0, selected - Math.floor(capacity / 2)));
}

/**
 * Move a page window by whole rows, clamped to the rows it holds.
 *
 * @param start - First row the window shows.
 * @param lines - Rows to move; negative moves towards the top.
 * @param total - Number of rows there are.
 * @param capacity - Rows the window holds.
 * @returns The window's new first row.
 */
export function scrolledStart(
  start: number,
  lines: number,
  total: number,
  capacity: number,
): number {
  const last = Math.max(0, total - capacity);
  return Math.max(0, Math.min(last, start + lines));
}
