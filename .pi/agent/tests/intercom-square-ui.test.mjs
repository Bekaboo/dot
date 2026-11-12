import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test, { describe } from "node:test";

import { createRenderer, squareCorners } from "../extensions/lib/intercom-frame.ts";

const plainTheme = { fg: (_color, text) => text };
const STYLED = /\x1b\[[0-9;]*m/g;

/**
 * Stand-in for pi-intercom's InlineMessageComponent: draws the same rounded
 * frame, so the overlay can be checked without loading the package (node
 * cannot type-strip TypeScript under node_modules).
 */
class StandInBox {
  static last;

  constructor(from, message, theme, replyCommand, bodyText, collapsed, expansionState) {
    Object.assign(this, { from, message, theme, replyCommand, bodyText, collapsed, expansionState });
    StandInBox.last = this;
  }

  render(width) {
    const inner = width - 2;
    return [
      `╭${"─".repeat(inner)}╮`,
      `│${this.message.content.text.padEnd(inner)}│`,
      `╰${"─".repeat(inner)}╯`,
    ];
  }
}

/**
 * Render one inbound message through the overlay's renderer.
 *
 * @param text - Message body.
 * @param options - Renderer options; `expanded` selects the full or collapsed box.
 * @returns Rendered lines.
 */
function renderMessage(text, { expanded = true, width = 60 } = {}) {
  const renderer = createRenderer(StandInBox);
  const message = {
    customType: "intercom_message",
    details: {
      from: { name: "planner", id: "6332faab", cwd: "~/repo" },
      message: { id: "m1", content: { text } },
      replyCommand: 'intercom({ action: "reply" })',
    },
  };

  return renderer(message, { expanded }, plainTheme).render(width);
}

describe("intercom-square-ui", () => {
  test("squareCorners swaps frame corners only", () => {
    // Frame lines, including the ANSI styling theme.fg wraps them in.
    assert.equal(squareCorners("╭ From: planner ╮"), "┌ From: planner ┐");
    assert.equal(squareCorners("╰──────────────╯"), "└──────────────┘");
    assert.equal(squareCorners("\x1b[2m╭\x1b[0mt\x1b[2m╮\x1b[0m"), "\x1b[2m┌\x1b[0mt\x1b[2m┐\x1b[0m");

    // Corner glyphs are ordinary text anywhere else on the line.
    const body = "│ glyphs ╭╮╰╯ stay ╮";
    assert.equal(squareCorners(body), body);
  });

  test("renders a square box and keeps glyphs inside the text", () => {
    const lines = renderMessage("glyphs ╭╮╰╯ stay rounded");
    const top = lines[0];
    const bottom = lines.at(-1);

    assert.ok(top.startsWith("┌") && top.endsWith("┐"), top);
    assert.ok(bottom.startsWith("└") && bottom.endsWith("┘"), bottom);
    assert.ok(lines[1].startsWith("│glyphs ╭╮╰╯ stay rounded"), lines[1]);

    // Corner swap must not change the box width.
    const widths = new Set(lines.map((line) => line.replace(STYLED, "").length));
    assert.deepEqual([...widths], [60]);

    // Messages without intercom details fall through to the host renderer.
    assert.equal(createRenderer(StandInBox)({ customType: "intercom_message" }, { expanded: true }, plainTheme), undefined);
  });

  test("expansion state survives rebuilds and follows the global option", () => {
    const renderer = createRenderer(StandInBox);
    const message = {
      customType: "intercom_message",
      details: { from: { name: "planner" }, message: { content: { text: "x" } } },
    };

    renderer(message, { expanded: true }, plainTheme);
    const state = StandInBox.last.expansionState;
    assert.equal(StandInBox.last.collapsed, false);

    // A click collapses the box without touching the global expand option.
    state.expanded = false;
    renderer(message, { expanded: true }, plainTheme);
    assert.equal(StandInBox.last.expansionState, state);
    assert.equal(state.expanded, false);

    // A global expand toggle resets the per-message state.
    renderer(message, { expanded: false }, plainTheme);
    assert.equal(state.expanded, false);
    renderer(message, { expanded: true }, plainTheme);
    assert.equal(state.expanded, true);
  });

  test("still binds to the pi-intercom internals it overrides", () => {
    const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
    const entry = source("../extensions/intercom-square-ui.ts");
    const intercom = source("../npm/node_modules/pi-intercom/index.ts");
    const component = source("../npm/node_modules/pi-intercom/ui/inline-message.ts");

    assert.match(component, /export class InlineMessageComponent/);
    assert.match(intercom, /registerMessageRenderer\(\s*["']intercom_message["']/);
    assert.match(entry, /registerMessageRenderer\(\s*["']intercom_message["']/);
  });
});
