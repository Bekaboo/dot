import assert from "node:assert/strict";
import test, { describe } from "node:test";

import { Text, visibleWidth } from "@earendil-works/pi-tui";

import {
  bodyRows,
  hintLine,
  PAGE_PADDING_X,
  scrolledStart,
  windowLabel,
} from "../../extensions/utils/page.ts";

const plainTheme = { fg: (_color, text) => text };
const STYLED = /\x1b\[[0-9;]*m/g;

/** Visible width of a rendered line, without its ANSI attributes. */
function plainWidth(line) {
  return visibleWidth(line.replace(STYLED, ""));
}

describe("page", () => {
  describe("bodyRows", () => {
    test("leaves the terminal's own rows and the box chrome out of the body", () => {
      // 20 rows: pi keeps 4, the box chrome takes 9, the blank line 1.
      assert.equal(bodyRows(() => 9, 20), 6);
      assert.equal(bodyRows(() => 5, 20), 10, "a slimmer box fits more rows");
    });

    test("never goes negative when the chrome alone fills the terminal", () => {
      assert.equal(bodyRows(() => 40, 20), 0);
      assert.equal(bodyRows(() => 0, 1), 0);
    });
  });

  describe("hintLine", () => {
    test("dims the hint and keeps it on one line at any width", () => {
      const hint = "Press Escape to close, up/down scroll  (7-12 of 12)";
      for (const width of [80, 40, 20, 8, 4]) {
        const rendered = new Text(
          hintLine(plainTheme, hint, width),
          PAGE_PADDING_X,
          1,
        ).render(width);
        // One hint line plus its top and bottom padding: a wrapped hint would
        // add rows and push the page's last rows out of the viewport.
        assert.equal(rendered.length, 3, `one hint line at width ${width}`);
        for (const line of rendered) assert.equal(plainWidth(line), width);
      }
    });

    test("shows the start of the hint, cut with an ellipsis", () => {
      const width = 10;
      const narrow = hintLine(plainTheme, "Press Escape to close", width)
        .replace(STYLED, "");
      assert.equal(
        plainWidth(narrow),
        width - PAGE_PADDING_X * 2,
        "the hint fills the line inside the padding before it is cut",
      );
      assert.match(narrow, /^Pre\.\.\.$/);
    });
  });

  describe("windowLabel", () => {
    test("says nothing while every row is shown", () => {
      assert.equal(windowLabel(0, 5, 5), "");
      assert.equal(windowLabel(0, 0, 0), "");
    });

    test("names the shown range within the rows that exist", () => {
      assert.equal(windowLabel(4, 6, 20), "  (5-10 of 20)");
      assert.equal(windowLabel(14, 6, 20), "  (15-20 of 20)");
    });

    test("still says something when the window holds no row at all", () => {
      assert.equal(windowLabel(0, 0, 20), "  (20 hidden)");
    });
  });

  describe("scrolledStart", () => {
    test("stays put while every row fits", () => {
      assert.equal(scrolledStart(0, 0, 3, 8), 0);
      assert.equal(scrolledStart(0, 5, 3, 8), 0);
    });

    test("stops at both ends of the rows", () => {
      assert.equal(scrolledStart(0, -1, 20, 6), 0, "no scroll above the top");
      assert.equal(scrolledStart(2, -1, 20, 6), 1);
      assert.equal(scrolledStart(14, 1, 20, 6), 14, "no scroll past the end");
      assert.equal(scrolledStart(0, 6, 20, 6), 6);
      assert.equal(scrolledStart(13, 99, 20, 6), 14);
    });
  });
});
