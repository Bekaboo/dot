/**
 * Square-corner rendering for pi-intercom's inline message box.
 *
 * This module deliberately has no runtime import from pi-intercom: `node
 * --test` refuses to type-strip files under node_modules, and the extension
 * itself imports the real component. Tests drive createRenderer with a stand-in
 * base class here, and the entry file binds the real one.
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
const FRAME_LINE = new RegExp(`^(${ANSI})([╭╰])(.*)([╮╯])(${ANSI})$`);

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
 * Replace the frame corners of one rendered line with square ones.
 *
 * Only box frames are rewritten: a line has to start and end with a corner
 * glyph, ignoring ANSI codes, so the same glyphs inside message text survive.
 */
export function squareCorners(line: string): string {
  const match = FRAME_LINE.exec(line);
  if (!match) return line;

  const [, prefix, open, body, close, suffix] = match;
  return `${prefix}${CORNERS[open]}${body}${CORNERS[close]}${suffix}`;
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
      return super.render(width).map(squareCorners);
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
