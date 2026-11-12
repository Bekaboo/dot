import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test, { describe } from "node:test";

const POPUP_UI = ["session-list", "compose", "handover-picker"];

describe("intercom-square-ui", () => {
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
});
