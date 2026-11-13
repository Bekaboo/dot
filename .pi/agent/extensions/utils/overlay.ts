/**
 * Bordered page widget shared by the `/subagents`, `/timers` and `/todos`
 * overlays.
 *
 * All three take pi's editor slot while they are open: a box with a title, a
 * summary, a body and a hint. Pi lays that slot out inside the dock under the
 * transcript, so a body taller than the terminal loses its last rows;
 * `OverlayPage` measures its own chrome and cuts the body to the rows the
 * terminal leaves, which keeps the hint and the bottom border visible.
 *
 * `/subagents` and `/timers` also drill from their list into one row's detail.
 * `DrillDown` keeps that navigation: Enter opens the selected row, Escape walks
 * back out, and a detail follows its newest lines until the reader scrolls up.
 * A detail can pin the lines that body hangs off, such as its spawn moment, in
 * the page's head so they stay on screen while the body scrolls.
 */

import {
  DynamicBorder,
  type KeybindingsManager,
  type Theme,
} from "@earendil-works/pi-coding-agent";
import {
  Container,
  type Keybinding,
  Text,
  type TUI,
  visibleWidth,
} from "@earendil-works/pi-tui";

import { bodyRows, hintLine, PAGE_PADDING_X, windowLabel } from "./page.ts";

/** Cursor in front of a selected row, as pi's select lists draw it. */
export const SELECTED_CURSOR = "→";

/**
 * Keys that move a list or a detail, and the rows each one moves.
 *
 * A page key moves a whole window, so its distance is resolved at the key press
 * against the rows the window holds.
 */
const MOVE_KEYS: readonly [Keybinding, (page: number) => number][] = [
  ["tui.select.up", () => -1],
  ["tui.select.down", () => 1],
  ["tui.select.pageUp", (page) => -page],
  ["tui.select.pageDown", (page) => page],
];

/**
 * Pad plain text on the right to a terminal width.
 *
 * @param text - Text without ANSI attributes.
 * @param width - Target terminal columns.
 * @returns The text followed by spaces, unchanged when already wide enough.
 */
export function padRight(text: string, width: number): string {
  const missing = width - visibleWidth(text);
  return missing > 0 ? text + " ".repeat(missing) : text;
}

/**
 * Pad plain text on the left to a terminal width.
 *
 * @param text - Text without ANSI attributes.
 * @param width - Target terminal columns.
 * @returns The text preceded by spaces, unchanged when already wide enough.
 */
export function padLeft(text: string, width: number): string {
  const missing = width - visibleWidth(text);
  return missing > 0 ? " ".repeat(missing) + text : text;
}

/**
 * Size of an open detail view, so scrolling knows how far it can move.
 */
export interface DetailViewport {
  /** Lines the detail view has in total. */
  total: number;
  /** Lines the window holds. */
  capacity: number;
}

/**
 * Rows a drill-down list shows and the row whose detail is open.
 */
export interface DrillDownState<T> {
  /** Index of the selected list row. */
  selected: number;
  /** Row whose detail is open, or undefined while the list is shown. */
  detail: T | undefined;
}

/**
 * Bordered page with a title, a summary, an optional fixed head, a body and a
 * hint.
 *
 * The body is measured and filled separately so a caller can size its rows
 * against the frame the terminal leaves before rendering them.
 */
export class OverlayPage {
  private readonly container = new Container();
  private readonly summaryText: Text;
  private readonly headText: Text;
  /** Rows the head holds, so the gap above the body is drawn only once. */
  private headRows = 0;
  private readonly bodyText: Text;
  private readonly footerText: Text;
  private readonly tui: TUI;
  private readonly theme: Theme;
  /** Rows the body held at the last `measure()`. */
  private capacity = 0;

  /**
   * @param tui - TUI the page renders into, for the rows the terminal leaves.
   * @param theme - Active theme.
   * @param title - Title drawn in the top row of the box.
   */
  constructor(tui: TUI, theme: Theme, title: string) {
    this.tui = tui;
    this.theme = theme;
    this.summaryText = new Text("", PAGE_PADDING_X, 0);
    this.headText = new Text("", PAGE_PADDING_X, 0);
    this.bodyText = new Text("", PAGE_PADDING_X, 0);
    this.footerText = new Text("", PAGE_PADDING_X, 1);

    const border = () =>
      new DynamicBorder((text) => theme.fg("borderMuted", text));
    this.container.addChild(border());
    this.container.addChild(
      new Text(theme.fg("accent", theme.bold(title)), PAGE_PADDING_X, 1),
    );
    this.container.addChild(this.summaryText);
    this.container.addChild(this.headText);
    this.container.addChild(this.bodyText);
    this.container.addChild(this.footerText);
    this.container.addChild(border());
  }

  /**
   * Replace the summary under the title.
   *
   * @param text - Styled summary, such as a count of the rows the page lists, or
   *   the settings a detail view repeats.
   */
  setSummary(text: string): void {
    this.summaryText.setText(text);
  }

  /**
   * Replace the fixed head between the summary and the body.
   *
   * Head rows stay put while the body window scrolls, so a view that follows the
   * end of its body can pin the context that body hangs off, such as the moment
   * it started. The head opens with the blank line that separates it from the
   * summary and sits directly on the body, which then draws no gap of its own.
   * An empty head reserves no rows.
   *
   * @param lines - Styled rows to pin above the body.
   */
  setHead(lines: readonly string[]): void {
    this.headRows = lines.length;
    this.headText.setText(lines.length > 0 ? `\n${lines.join("\n")}` : "");
  }

  /**
   * Rows the body may fill at this width, keeping the chrome and hint visible.
   *
   * The body is emptied and the hint set first, so the measured frame -- title,
   * summary, head and hint -- matches the one the caller then fills.
   *
   * @param width - Page width, including the text padding.
   * @param hint - Hint the page will show, measured without its row count.
   * @returns Lines left for the body, or 0 when only the chrome fits.
   */
  measure(width: number, hint: string): number {
    this.bodyText.setText("");
    this.footerText.setText(hintLine(this.theme, hint, width));
    this.capacity = bodyRows(
      () => this.container.render(width).length,
      this.tui.terminal.rows,
      // A head opens with the gap and is measured with it.
      this.headRows > 0 ? 0 : 1,
    );
    return this.capacity;
  }

  /** Rows the body held at the last `measure()`, for a view's page keys. */
  get rowCapacity(): number {
    return this.capacity;
  }

  /**
   * Show a window of rows, with a hint that says how to move it and which rows
   * are on screen.
   *
   * The scroll keys are named only while the window hides rows, and the hint
   * ends with the range on screen, so a reader knows how much is left.
   *
   * @param rows - Every row of the view, rendered one per line.
   * @param start - Index of the window's first row.
   * @param capacity - Rows the window holds.
   * @param hint - Hint for the view, without its scroll and range suffixes.
   * @param width - Page width, including the text padding.
   */
  setWindow(
    rows: readonly string[],
    start: number,
    capacity: number,
    hint: string,
    width: number,
  ): void {
    const shown = rows.slice(start, start + Math.max(0, capacity));
    // The head already drew the gap above the body.
    const gap = this.headRows > 0 ? "" : "\n";
    this.bodyText.setText(shown.length > 0 ? `${gap}${shown.join("\n")}` : "");
    const footer =
      shown.length < rows.length ? `${hint}, up/down scroll` : hint;
    this.footerText.setText(
      hintLine(
        this.theme,
        `${footer}${windowLabel(start, shown.length, rows.length)}`,
        width,
      ),
    );
  }

  /**
   * Render the page at this width.
   *
   * @param width - Page width, including the text padding.
   * @returns The box lines.
   */
  render(width: number): string[] {
    return this.container.render(width);
  }

  /** Re-render every child after the theme or the rows changed. */
  invalidate(): void {
    this.container.invalidate();
  }
}

/**
 * List-and-detail navigation for a page whose rows drill into a detail view.
 *
 * The list keeps one row selected and Enter opens its detail; Escape closes the
 * detail first and only then the page. A detail opens on its newest lines and
 * follows them as they arrive, until scrolling up pins the window; scrolling
 * back to the end follows the newest lines again.
 */
export class DrillDown {
  private readonly requestRender: () => void;
  /** Index of the selected list row. */
  private selectedIndex = 0;
  /** Key of the row whose detail is open, or undefined on the list. */
  private detailKey: string | undefined;
  /** First detail line the window shows, or undefined to follow the end. */
  private detailStart: number | undefined;
  /** Size of the open detail at the last `detailWindow()`. */
  private viewport: DetailViewport | undefined;

  /**
   * @param requestRender - Redraws the page after a key moved it.
   */
  constructor(requestRender: () => void) {
    this.requestRender = requestRender;
  }

  /**
   * Settle the selection and the open detail against the rows that exist now,
   * so a row that went away cannot leave either pointing at nothing.
   *
   * @param rows - Rows the list has now.
   * @param keyOf - Key that identifies one row.
   * @returns The selected index, and the row whose detail is open, if any.
   */
  sync<T>(rows: readonly T[], keyOf: (row: T) => string): DrillDownState<T> {
    this.selectedIndex = Math.max(
      0,
      Math.min(this.selectedIndex, rows.length - 1),
    );
    const detail = rows.find((row) => keyOf(row) === this.detailKey);
    if (!detail) this.closeDetail();
    return { selected: this.selectedIndex, detail };
  }

  /**
   * First line of the open detail to draw.
   *
   * @param total - Lines the detail has.
   * @param capacity - Lines the window holds.
   * @returns Index of the first line, following the end until scrolled up.
   */
  detailWindow(total: number, capacity: number): number {
    const last = Math.max(0, total - capacity);
    // A detail that fits has no pinned window: lines that arrive later should
    // follow the end again.
    if (last === 0) this.detailStart = undefined;
    const start =
      this.detailStart === undefined ? last : Math.min(this.detailStart, last);
    this.viewport = { total, capacity };
    return start;
  }

  /**
   * Apply one key press to the list or the open detail.
   *
   * @param data - Raw input the page received.
   * @param keybindings - User keybindings, read through pi's action names.
   * @param rows - Keys of the list rows, in order.
   * @param capacity - Rows the list window holds, for its page keys.
   * @returns true when the key asks for the whole page to close.
   */
  handleInput(
    data: string,
    keybindings: KeybindingsManager,
    rows: readonly string[],
    capacity: number,
  ): boolean {
    if (keybindings.matches(data, "tui.select.cancel")) {
      if (this.detailKey === undefined) return true;
      this.closeDetail();
      this.requestRender();
      return false;
    }
    if (this.detailKey === undefined) {
      this.moveList(data, keybindings, rows, capacity);
    } else {
      this.scrollDetail(data, keybindings);
    }
    return false;
  }

  /** Forget the open detail and the window it pinned. */
  private closeDetail(): void {
    this.detailKey = undefined;
    this.detailStart = undefined;
    this.viewport = undefined;
  }

  /** Move the list, or open the selected row on confirm. */
  private moveList(
    data: string,
    keybindings: KeybindingsManager,
    rows: readonly string[],
    capacity: number,
  ): void {
    const page = Math.max(1, capacity);
    for (const [action, rowsOf] of MOVE_KEYS) {
      if (!keybindings.matches(data, action)) continue;
      this.selectedIndex = Math.max(
        0,
        Math.min(rows.length - 1, this.selectedIndex + rowsOf(page)),
      );
      this.requestRender();
      return;
    }
    const row = rows[this.selectedIndex];
    if (row === undefined) return;
    if (!keybindings.matches(data, "tui.select.confirm")) return;
    this.detailKey = row;
    this.detailStart = undefined;
    this.viewport = undefined;
    this.requestRender();
  }

  /** Scroll the open detail with the list keys. */
  private scrollDetail(data: string, keybindings: KeybindingsManager): void {
    const page = Math.max(1, this.viewport?.capacity ?? 1);
    for (const [action, rowsOf] of MOVE_KEYS) {
      if (!keybindings.matches(data, action)) continue;
      this.scroll(rowsOf(page));
      return;
    }
  }

  /** Move the detail window, following the end again when it reaches it. */
  private scroll(lines: number): void {
    const view = this.viewport;
    if (!view) return;
    const last = Math.max(0, view.total - view.capacity);
    if (last === 0) return;
    // Resolve a followed end before moving, so repeated keys add up even when
    // the page has not rendered between them.
    const from = this.detailStart ?? last;
    const next = Math.max(0, Math.min(last, from + lines));
    this.detailStart = next >= last ? undefined : next;
    this.requestRender();
  }
}
