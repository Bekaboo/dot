/**
 * Vim-ruler-style scroll position in the footer: Top / Bot / xx% / All.
 *
 * Replaces the built-in footer with a minimal one (cwd, git branch, model,
 * scroll position) and keeps extension statuses from ctx.ui.setStatus().
 *
 * With ruler showing scroll position, the scrollbar is redundant, so we
 * disable it with "fullscreenScrollbar": "hidden" in settings.json.
 */

import type {
  ExtensionAPI,
  ExtensionContext,
  ReadonlyFooterDataProvider,
  Theme,
} from "@earendil-works/pi-coding-agent";

import {
  type TUI,
  truncateToWidth,
  visibleWidth,
} from "@earendil-works/pi-tui";

/** Runtime shape of the transcript ScrollView used by the ruler. */
type ScrollViewLike = {
  /** Number of lines scrolled past the top. */
  readonly scrollTop: number;
  /** Total number of rendered transcript lines. */
  readonly contentHeight: number;
  /** Number of transcript lines that fit in the viewport. */
  readonly viewportHeight: number;
  /** Whether the viewport is pinned to the newest output. */
  readonly isFollowingEnd: boolean;
};

/** Footer component contract expected by ctx.ui.setFooter(). */
type FooterComponent = {
  /** Release the branch-change subscription. */
  dispose(): void;
  /** Drop any cached render state (none here, so a no-op). */
  invalidate(): void;
  /**
   * Render the footer for one frame.
   *
   * @param width - Available terminal columns.
   * @returns One or two styled lines, each fitting within `width`.
   */
  render(width: number): string[];
};

/**
 * Read the fullscreen transcript's scroll view.
 *
 * `getPrimaryScrollView` exists on TuiAltScreen at runtime but is private in
 * the published typings, so it is feature-detected through a narrowed cast.
 *
 * @param tui - Active TUI instance passed to the footer factory.
 * @returns The transcript scroll view, or undefined when unavailable.
 */
function getTranscriptScroll(tui: TUI): ScrollViewLike | undefined {
  const runtimeTui = tui as TUI & {
    getPrimaryScrollView?: () => ScrollViewLike;
  };
  return typeof runtimeTui.getPrimaryScrollView === "function"
    ? runtimeTui.getPrimaryScrollView()
    : undefined;
}

/**
 * Format the transcript scroll offset as a Vim-style ruler.
 *
 * @param tui - Active TUI instance passed to the footer factory.
 * @returns `All` when everything fits, `Top` at the top, `Bot` at the end,
 *   `N%` in between, or an empty string when no scroll view is available.
 */
function formatScrollPosition(tui: TUI): string {
  const scrollView = getTranscriptScroll(tui);
  if (!scrollView) return "";

  const maxScrollTop = Math.max(
    0,
    scrollView.contentHeight - scrollView.viewportHeight,
  );
  if (maxScrollTop === 0) return "All";
  if (scrollView.scrollTop <= 0) return "Top";
  if (scrollView.isFollowingEnd || scrollView.scrollTop >= maxScrollTop) {
    return "Bot";
  }
  return `${Math.round((scrollView.scrollTop / maxScrollTop) * 100)}%`;
}

/**
 * Render the status line contributed by ctx.ui.setStatus().
 *
 * @param theme - Active footer theme.
 * @param footerData - Provider exposing extension statuses.
 * @param width - Available terminal columns.
 * @returns A styled status line, or undefined when no statuses are set.
 */
function renderStatusLine(
  theme: Theme,
  footerData: ReadonlyFooterDataProvider,
  width: number,
): string | undefined {
  const statuses = [...footerData.getExtensionStatuses().values()];
  if (statuses.length === 0) return undefined;

  const text = statuses
    .map((status) => status.replace(/[\r\n\t]+/g, " ").trim())
    .join(" ");
  return truncateToWidth(theme.fg("dim", text), width);
}

/**
 * Build every footer line for the current frame.
 *
 * @param ctx - Session context with the working directory and live model.
 * @param tui - Active TUI instance.
 * @param theme - Active footer theme.
 * @param footerData - Provides git branch and extension statuses.
 * @param width - Available terminal columns.
 * @returns The footer lines, main line first, status line second if present.
 */
function renderFooterLines(
  ctx: ExtensionContext,
  tui: TUI,
  theme: Theme,
  footerData: ReadonlyFooterDataProvider,
  width: number,
): string[] {
  const branch = footerData.getGitBranch();
  const cwd = branch ? `${ctx.cwd} (${branch})` : ctx.cwd;
  const left = theme.fg("dim", cwd);

  const ruler = tui.mode === "fullscreen" ? formatScrollPosition(tui) : "";
  const model = theme.fg("dim", ctx.model?.id ?? "no-model");
  const right = ruler ? `${model}  ${theme.fg("accent", ruler)}` : model;

  const padding = Math.max(1, width - visibleWidth(left) - visibleWidth(right));
  const lines = [truncateToWidth(left + " ".repeat(padding) + right, width)];

  const statusLine = renderStatusLine(theme, footerData, width);
  if (statusLine) lines.push(statusLine);
  return lines;
}

/**
 * Create the footer component installed through ctx.ui.setFooter().
 *
 * @param ctx - Session context with the working directory and live model.
 * @param tui - Active TUI instance.
 * @param theme - Active footer theme.
 * @param footerData - Provides git branch and extension statuses.
 * @returns Footer component that renders on every frame.
 */
function createFooter(
  ctx: ExtensionContext,
  tui: TUI,
  theme: Theme,
  footerData: ReadonlyFooterDataProvider,
): FooterComponent {
  const unsubscribe = footerData.onBranchChange(() => tui.requestRender());

  return {
    dispose: unsubscribe,
    invalidate() { },
    render: (width) => renderFooterLines(ctx, tui, theme, footerData, width),
  };
}

/**
 * Register the extension with Pi.
 *
 * @param pi - Extension API used to hook the session lifecycle.
 */
export default function vimRuler(pi: ExtensionAPI): void {
  pi.on("session_start", (_event, ctx) => {
    ctx.ui.setFooter((tui, theme, footerData) =>
      createFooter(ctx, tui, theme, footerData),
    );
  });
}
