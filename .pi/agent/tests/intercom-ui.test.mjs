import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test, { describe } from "node:test";

import { squareThemeFrames } from "../extensions/utils/intercom-frame.ts";

const POPUP_UI = ["session-list", "compose", "handover-picker"];
const BG_RESET = "\x1b[49m";

/** Source of one pi-intercom popup. */
function popupSource(name) {
  return readFileSync(
    new URL(`../npm/node_modules/pi-intercom/ui/${name}.ts`, import.meta.url),
    "utf8",
  );
}

/**
 * A theme stand-in that names the styles it paints instead of emitting SGR, so
 * a test can read where a style starts and stops.
 *
 * @returns The theme, with `squareThemeFrames` already applied.
 */
function fakeTheme() {
  class FakeTheme {
    fg(color, text) {
      return `<fg ${color}>${text}</fg>`;
    }
    getBgAnsi(color) {
      return `<bg ${color}>`;
    }
  }
  const theme = new FakeTheme();
  squareThemeFrames(theme);
  return theme;
}

/**
 * One popup row, composed the way pi-intercom composes it: a left border, the
 * row's text padded to the content width, and a closing border.
 *
 * @param theme - Theme the row is drawn through.
 * @param text - Row text, already styled.
 * @returns The composed row.
 */
function popupRow(theme, text) {
  const visible = [...text.replace(/<[^>]+>/g, "")].length;
  return `${theme.fg("accent", "│")}${text}${" ".repeat(Math.max(0, 20 - visible))}${theme.fg("accent", "│")}`;
}

describe("intercom-ui", () => {
  test("still binds to the pi-intercom internals it overrides", () => {
    const source = (path) =>
      readFileSync(new URL(path, import.meta.url), "utf8");
    const entry = source("../extensions/intercom-ui.ts");
    const intercom = source("../npm/node_modules/pi-intercom/index.ts");
    const component = source(
      "../npm/node_modules/pi-intercom/ui/inline-message.ts",
    );

    assert.match(component, /export class InlineMessageComponent/);
    assert.match(
      intercom,
      /registerMessageRenderer\(\s*["']intercom_message["']/,
    );
    assert.match(entry, /registerMessageRenderer\(\s*["']intercom_message["']/);
    assert.match(entry, /squareThemeFrames\(ctx\.ui\.theme\)/);
  });

  test("popup borders are single lines so the theme can square them", () => {
    // squareThemeFrames can only rewrite a border that reaches theme.fg() as
    // one string, so a popup that draws its frame piecewise would silently
    // keep rounded corners.
    for (const name of POPUP_UI) {
      const source = popupSource(name);

      assert.match(
        source,
        /`╭[^`]*╮`/,
        `${name} draws its top border as one line`,
      );
      assert.match(
        source,
        /`╰[^`]*╯`/,
        `${name} draws its bottom border as one line`,
      );
    }
  });

  test("popup rows keep the pieces the selection band is drawn on", () => {
    // The band opens on the cursor's own theme.fg() call and ends at the row's
    // closing border, so both have to stay whole arguments.
    for (const name of POPUP_UI) {
      const source = popupSource(name);

      assert.match(
        source,
        /border\("│"\)/,
        `${name} draws a row border through theme.fg`,
      );
    }
    for (const name of ["session-list", "handover-picker"]) {
      assert.match(
        popupSource(name),
        /theme\.fg\("accent", "→ "\)/,
        `${name} draws its cursor through theme.fg`,
      );
    }
  });

  test("puts the cursor row on Pi's selection background", () => {
    const theme = fakeTheme();
    const title = (text) => theme.fg("accent", text);
    const selected = popupRow(theme, `${title("→ ")}${title("session-a")}`);
    const other = popupRow(theme, `  session-b`);

    assert.match(selected, /<bg selectedBg><fg accent>› <\/fg>/);
    assert.equal(
      selected.split("<bg selectedBg>").length - 1,
      1,
      "the row opens the band once",
    );
    assert.ok(
      selected.startsWith(`${BG_RESET}<fg accent>│</fg>`),
      "the left border stays off the band",
    );
    assert.ok(
      selected.endsWith(`${BG_RESET}<fg accent>│</fg>`),
      "the band stops before the closing border",
    );
    assert.doesNotMatch(other, /<bg selectedBg>/, "other rows stay plain");
  });
});
