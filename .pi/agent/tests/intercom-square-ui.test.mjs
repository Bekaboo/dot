import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test, { describe } from "node:test";

import { createRenderer, squareFrames, squareThemeFrames } from "../extensions/lib/intercom-frame.ts";

const plainTheme = { fg: (_color, text) => text };
const STYLED = /\x1b\[[0-9;]*m/g;
const POPUP_UI = ["session-list", "compose", "handover-picker"];

/**
 * Fresh stand-in for pi's Theme class, so patching it in one test cannot leak
 * into the next. `prefix` proves the swap keeps running with the right `this`.
 */
function fakeThemeClass() {
  return class FakeTheme {
    constructor(prefix = "") {
      this.prefix = prefix;
    }

    fg(color, text) {
      return `${this.prefix}<${color}>${text}</${color}>`;
    }
  };
}

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
  test("squareFrames swaps frame corners only", () => {
    // Frame lines, including the ANSI styling theme.fg wraps them in.
    assert.equal(squareFrames("╭ From: planner ╮"), "┌ From: planner ┐");
    assert.equal(squareFrames("╰──────────────╯"), "└──────────────┘");
    assert.equal(squareFrames("\x1b[2m╭\x1b[0mt\x1b[2m╮\x1b[0m"), "\x1b[2m┌\x1b[0mt\x1b[2m┐\x1b[0m");
    assert.equal(squareFrames("╭─╮\n│x│\n╰─╯"), "┌─┐\n│x│\n└─┘");

    // Corner glyphs are ordinary text anywhere else on the line.
    const body = "│ glyphs ╭╮╰╯ stay ╮";
    assert.equal(squareFrames(body), body);
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
    assert.match(entry, /squareThemeFrames\(ctx\.ui\.theme\)/);
  });

  test("popup borders are single lines so the theme can square them", () => {
    // squareThemeFrames can only rewrite a border that reaches theme.fg() as
    // one string, so a popup that draws its frame piecewise would silently
    // keep rounded corners.
    for (const name of POPUP_UI) {
      const path = `../npm/node_modules/pi-intercom/ui/${name}.ts`;
      const source = readFileSync(new URL(path, import.meta.url), "utf8");

      assert.match(source, /`╭[^`]*╮`/, `${name} draws its top border as one line`);
      assert.match(source, /`╰[^`]*╯`/, `${name} draws its bottom border as one line`);
    }
  });

  describe("squareThemeFrames", () => {
    test("squares frame lines and leaves other styled text alone", () => {
      const theme = new (fakeThemeClass())("~");
      squareThemeFrames(theme);

      assert.equal(theme.fg("accent", "╭──────╮"), "~<accent>┌──────┐</accent>");
      assert.equal(theme.fg("accent", "╰──────╯"), "~<accent>└──────┘</accent>");

      const body = "~<accent>│ ╭x╮ │</accent>";
      assert.equal(theme.fg("accent", "│ ╭x╮ │"), body);
    });

    test("squares a whole styled block, keeping its styling per call", () => {
      const theme = new (fakeThemeClass())();
      squareThemeFrames(theme);

      assert.equal(
        theme.fg("accent", "╭─╮\n│x│\n╰─╯"),
        "<accent>┌─┐\n│x│\n└─┘</accent>",
      );
    });

    test("covers themes created after the swap, such as a theme switch", () => {
      const FakeTheme = fakeThemeClass();
      squareThemeFrames(new FakeTheme());

      assert.equal(new FakeTheme().fg("accent", "╭─╮"), "<accent>┌─┐</accent>");
    });
  });
});
