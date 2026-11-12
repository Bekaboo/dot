import assert from "node:assert/strict";
import test, { describe } from "node:test";

import {
  createRenderer,
  squareFrames,
  squareThemeFrames,
} from "../../extensions/utils/intercom-frame.ts";

const plainTheme = { fg: (_color, text) => text };
const STYLED = /\x1b\[[0-9;]*m/g;

/**
 * Stand-in for pi's Theme class, so patching a prototype stays inside one test.
 * `prefix` proves the swap keeps running with the right `this`.
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
 * Stand-in for pi-intercom's InlineMessageComponent. It draws the same rounded
 * frame, so the renderer can be checked without loading the package: node
 * cannot type-strip TypeScript under node_modules.
 */
class StandInBox {
  constructor(...args) {
    [this.from, this.message, this.theme, this.replyCommand, this.bodyText, this.collapsed, this.expansionState] = args;
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

/** Build an `intercom_message` the way pi-intercom emits one. */
function intercomMessage(text) {
  return {
    customType: "intercom_message",
    details: {
      from: { name: "planner", id: "6332faab", cwd: "~/repo" },
      message: { id: "m1", content: { text } },
      replyCommand: 'intercom({ action: "reply" })',
      bodyText: text,
    },
  };
}

/**
 * Render one inbound message through the overlay's renderer.
 *
 * @param text - Message body.
 * @param options - Renderer options; `expanded` selects the full or collapsed box.
 * @returns Rendered lines.
 */
function renderMessage(text, { expanded = true, width = 60, renderer = createRenderer(StandInBox) } = {}) {
  return renderer(intercomMessage(text), { expanded }, plainTheme).render(width);
}

describe("squareFrames", () => {
  test("swaps the corners of every frame line", () => {
    assert.equal(squareFrames("╭ From: planner ╮"), "┌ From: planner ┐");
    assert.equal(squareFrames("╰──────────────╯"), "└──────────────┘");
    assert.equal(squareFrames("╭─╮\n│x│\n╰─╯"), "┌─┐\n│x│\n└─┘");
  });

  test("leaves corner glyphs that are not a frame alone", () => {
    const body = "│ glyphs ╭╮╰╯ stay ╮";
    assert.equal(squareFrames(body), body);

    // Both ends of the line have to be corners; one alone is ordinary text.
    assert.equal(squareFrames("╭ From: planner"), "╭ From: planner");
    assert.equal(squareFrames("From: planner ╮"), "From: planner ╮");
    assert.equal(squareFrames("╭─╮ trailing text"), "╭─╮ trailing text");
  });

  test("keeps the ANSI styling around the corners", () => {
    assert.equal(
      squareFrames("\x1b[2m╭\x1b[0mt\x1b[2m╮\x1b[0m"),
      "\x1b[2m┌\x1b[0mt\x1b[2m┐\x1b[0m",
    );
    assert.equal(squareFrames("\x1b[1m╭─╮\x1b[0m"), "\x1b[1m┌─┐\x1b[0m");
    assert.equal(squareFrames("\x1b[1m╰─╯\x1b[0m"), "\x1b[1m└─┘\x1b[0m");
  });
});

describe("squareThemeFrames", () => {
  test("squares frame lines and leaves other styled text alone", () => {
    const theme = new (fakeThemeClass())("~");
    squareThemeFrames(theme);

    assert.equal(theme.fg("accent", "╭──────╮"), "~<accent>┌──────┐</accent>");
    assert.equal(theme.fg("accent", "╰──────╯"), "~<accent>└──────┘</accent>");
    assert.equal(theme.fg("accent", "│ ╭x╮ │"), "~<accent>│ ╭x╮ │</accent>");
  });

  test("squares a whole styled block in one call", () => {
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

  test("a second swap leaves the original fg in place exactly once", () => {
    class CountingTheme {
      static calls = 0;

      fg(_color, text) {
        CountingTheme.calls++;
        return text;
      }
    }

    squareThemeFrames(new CountingTheme());
    squareThemeFrames(new CountingTheme());

    new CountingTheme().fg("accent", "╭─╮");
    assert.equal(CountingTheme.calls, 1);
  });
});

describe("createRenderer", () => {
  test("renders a square box without changing its width or body", () => {
    const lines = renderMessage("glyphs ╭╮╰╯ stay rounded");

    assert.ok(lines[0].startsWith("┌") && lines[0].endsWith("┐"), lines[0]);
    assert.ok(lines.at(-1).startsWith("└") && lines.at(-1).endsWith("┘"), lines.at(-1));
    assert.ok(lines[1].startsWith("│glyphs ╭╮╰╯ stay rounded"), lines[1]);

    const widths = new Set(lines.map((line) => line.replace(STYLED, "").length));
    assert.deepEqual([...widths], [60]);
  });

  test("falls through to the host renderer without intercom details", () => {
    const renderer = createRenderer(StandInBox);
    assert.equal(renderer({ customType: "intercom_message" }, { expanded: true }, plainTheme), undefined);
  });

  test("builds the component from the message details", () => {
    const renderer = createRenderer(StandInBox);
    const message = intercomMessage("hello");
    const component = renderer(message, { expanded: false }, plainTheme);

    assert.equal(component.message, message.details.message);
    assert.equal(component.from, message.details.from);
    assert.equal(component.replyCommand, message.details.replyCommand);
    assert.equal(component.bodyText, message.details.bodyText);
    assert.equal(component.collapsed, true);
  });

  test("keeps per-message expansion state across rebuilds", () => {
    const renderer = createRenderer(StandInBox);
    const first = intercomMessage("one");
    const second = intercomMessage("two");

    const expanded = renderer(first, { expanded: true }, plainTheme);
    assert.equal(expanded.collapsed, false);

    // A click collapses the box without touching the global expand option;
    // rebuilding the same message must find the state again.
    expanded.expansionState.expanded = false;
    const rebuilt = renderer(first, { expanded: true }, plainTheme);
    assert.equal(rebuilt.expansionState, expanded.expansionState);
    assert.equal(rebuilt.expansionState.expanded, false);

    // Another message owns its own state.
    const other = renderer(second, { expanded: true }, plainTheme);
    assert.notEqual(other.expansionState, expanded.expansionState);
  });

  test("resets the per-message state when the global option flips", () => {
    const renderer = createRenderer(StandInBox);
    const message = intercomMessage("x");

    const state = renderer(message, { expanded: true }, plainTheme).expansionState;
    state.expanded = false;

    assert.equal(renderer(message, { expanded: false }, plainTheme).expansionState, state);
    assert.equal(state.expanded, false);
    assert.equal(state.globalExpanded, false);

    renderer(message, { expanded: true }, plainTheme);
    assert.equal(state.expanded, true);
    assert.equal(state.globalExpanded, true);
  });
});
