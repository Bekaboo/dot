/**
 * ANSI text helpers for rows that an enclosing component paints a background
 * behind, such as a tool block or a selected list row.
 */

import { truncateToWidth } from "@earendil-works/pi-tui";

/** SGR reset of every attribute. */
const FULL_RESET = "\x1b[0m";

/**
 * SGR reset of bold, dim and the foreground only.
 *
 * The background is left alone, which is the point: it is owned by the
 * enclosing component and still being painted.
 */
const ATTRIBUTE_RESET = "\x1b[22;39m";

/** SGR faint on, then off again with the dim it sets. */
const FAINT = "\x1b[2m";
const FAINT_OFF = "\x1b[22m";

/**
 * Style a cut mark faint, so the cut reads as secondary to the row it ends.
 *
 * @param ellipsis - Plain mark appended to a cut row.
 * @returns The mark drawn faint, or nothing when there is no mark.
 */
function dimmed(ellipsis: string): string {
  return ellipsis ? `${FAINT}${ellipsis}${FAINT_OFF}` : "";
}

/**
 * Truncate styled text to a width while keeping an enclosing background.
 *
 * `truncateToWidth` ends the kept prefix with a full SGR reset, so the
 * ellipsis, and everything after it, would fall back to the terminal's default
 * background instead of the block's or the selected row's. Swapping that reset
 * for one that clears only bold/dim and the foreground keeps the background
 * running to the end of the line. The mark itself is drawn faint, so a row cut
 * from bright text does not end in a bright ellipsis.
 *
 * @param text - Styled text to cut.
 * @param width - Row width in cells.
 * @param ellipsis - Plain mark appended to a cut row.
 * @param pad - Whether to pad the row to the full width.
 * @returns The text, cut to the width with no full reset left in it.
 */
export function truncateKeepingBackground(
  text: string,
  width: number,
  ellipsis = "...",
  pad = false,
): string {
  return truncateToWidth(text, width, dimmed(ellipsis), pad).replaceAll(
    FULL_RESET,
    ATTRIBUTE_RESET,
  );
}
