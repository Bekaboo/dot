/**
 * Glyph alignment for pi-intercom's message box and popups.
 *
 * Two seams are used because the two kinds of frame are drawn differently.
 * The inline message box is a registered renderer, so `createRenderer` can
 * subclass pi-intercom's component. Its popups (`/intercom` session list,
 * compose box, handover picker) are constructed inside pi-intercom and expose
 * no renderer registration; Pi also re-evaluates imports per extension, so
 * patching those component classes from here would not reach the instances
 * pi-intercom builds. What both sides share is the `Theme`, and each popup
 * border line is styled as one `theme.fg()` call, so `squareThemeFrames` swaps
 * the corners there. The selected-row cursor takes the same route: pi-intercom
 * draws `→ ` through `theme.fg` where Pi's own selectors use `› `.
 *
 * Workaround: this module takes pi-intercom's component class as an argument
 * instead of importing it. pi-intercom ships TypeScript inside node_modules,
 * where `node --test` refuses to type-strip
 * (ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING), so a test that imported the
 * class directly could not load. Tests pass a stand-in class, the entry file
 * imports the real one and binds it.
 *
 * Drop the indirection once tests compile dependency TypeScript, for example by
 * running under tsx, if the rest of the suite can move with it.
 */

import type { MessageRenderer, Theme } from "@earendil-works/pi-coding-agent";
import type { Component } from "@earendil-works/pi-tui";
import type {
  Message,
  SessionInfo,
} from "../../npm/node_modules/pi-intercom/types.ts";

const ANSI = "(?:\\x1b\\[[0-9;]*m)*";
const CORNERS: Record<string, string> = {
  "╭": "┌",
  "╮": "┐",
  "╰": "└",
  "╯": "┘",
};
// `m` matches line by line, so one replace covers a whole styled block without
// splitting it first.
const FRAME_LINE = new RegExp(`^(${ANSI})([╭╰])(.*)([╮╯])(${ANSI})$`, "gm");
// Whole-argument matches only: pi-intercom passes the cursor as one styled
// string, while the same glyph inside body text keeps its original meaning.
const CURSORS: Record<string, string> = {
  "→ ": "› ",
};
const SQUARED = Symbol.for("pi.intercom-ui.squared");

/** A theme class prototype, marked once it carries the glyph swaps. */
type FrameThemePrototype = Theme & { [key: symbol]: unknown };

/** Details pi-intercom attaches to every `intercom_message` it emits. */
export interface MessageDetails {
  from: SessionInfo;
  message: Message;
  replyCommand?: string;
  bodyText?: string;
}

/** Per-message expansion state, shared with the component so clicks persist. */
export interface ExpansionState {
  globalExpanded: boolean;
  expanded: boolean;
}

/** Constructor shape of pi-intercom's InlineMessageComponent. */
export interface MessageComponentClass {
  new (
    from: SessionInfo,
    message: Message,
    theme: Theme,
    replyCommand?: string,
    bodyText?: string,
    collapsed?: boolean,
    expansionState?: ExpansionState,
  ): Component;
}

/**
 * Replace rounded frame corners with square ones.
 *
 * Only box frames are rewritten: a line has to start and end with a corner
 * glyph, ignoring ANSI codes, so the same glyphs inside text survive. Lines are
 * matched one by one, so a whole styled block can be passed in.
 */
export function squareFrames(text: string): string {
  return text.replace(
    FRAME_LINE,
    (_line, prefix, open, body, close, suffix) =>
      `${prefix}${CORNERS[open]}${body}${CORNERS[close]}${suffix}`,
  );
}

/**
 * Rewrite the glyphs pi-intercom hardcodes: frame corners and the row cursor.
 */
function restyle(text: string): string {
  return squareFrames(CURSORS[text] ?? text);
}

/**
 * Square every frame drawn through a theme, and align its row cursor.
 *
 * Popup frames leave as one `theme.fg()` call per border line, so the glyph
 * swap belongs on `fg` itself. The prototype is patched rather than the
 * instance so themes created later, such as after `/theme`, are covered too;
 * the mark keeps an extension reload from stacking wrappers.
 *
 * @param theme - Pi's live theme, as handed to extensions as `ctx.ui.theme`.
 */
export function squareThemeFrames(theme: Theme): void {
  // Extensions get a proxy over the live theme, and its own prototype is
  // Object.prototype, so the class is reached through `constructor`.
  const prototype = (
    theme.constructor as unknown as { prototype: FrameThemePrototype }
  ).prototype;
  if (prototype[SQUARED]) return;

  const fg = prototype.fg;
  prototype.fg = function (this: Theme, color, text) {
    return fg.call(this, color, restyle(text));
  };
  prototype[SQUARED] = true;
}

/**
 * Build the `intercom_message` renderer on top of a message component class.
 *
 * Reuses pi-intercom's rendering and only swaps the four frame glyphs, so
 * wrapping, attachments, reply hints and click-to-expand keep upstream
 * behaviour. The per-message state is keyed by the outer custom message, which
 * the host reuses across rebuilds.
 *
 * @param Base - pi-intercom's InlineMessageComponent, or a stand-in in tests.
 * @returns A renderer for pi.registerMessageRenderer("intercom_message", ...).
 */
export function createRenderer(
  Base: MessageComponentClass,
): MessageRenderer<MessageDetails> {
  class SquareCornersMessage extends Base {
    render(width: number): string[] {
      return super.render(width).map(squareFrames);
    }
  }

  const expansionStates = new WeakMap<object, ExpansionState>();

  return (message, options, theme) => {
    const details = message.details;
    if (!details) return undefined;

    let expansionState = expansionStates.get(message);
    if (!expansionState) {
      expansionState = {
        globalExpanded: options.expanded,
        expanded: options.expanded,
      };
      expansionStates.set(message, expansionState);
    } else if (expansionState.globalExpanded !== options.expanded) {
      expansionState.globalExpanded = options.expanded;
      expansionState.expanded = options.expanded;
    }

    return new SquareCornersMessage(
      details.from,
      details.message,
      theme,
      details.replyCommand,
      details.bodyText,
      !options.expanded,
      expansionState,
    );
  };
}
