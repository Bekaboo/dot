/**
 * Tests for the one-line tool row pieces: the truncating row, the first-line
 * preview, the header, and the expanded argument list.
 */

import assert from "node:assert/strict";
import { describe, test } from "node:test";
import {
  expandedArgs,
  firstLine,
  OneLine,
  resultText,
  toolRowHeader,
} from "../../extensions/utils/tool-row.ts";

/** A theme that keeps text as it is, so a row reads as plain text. */
const theme = {
  fg: (_color, text) => text,
  bold: (text) => text,
};

/**
 * Render a component and drop the color resets `truncateToWidth` leaves behind.
 *
 * @param component - Component to render.
 * @param width - Row width in cells.
 * @returns One plain line per rendered row.
 */
function plain(component, width) {
  return component
    .render(width)
    .map((line) => line.replace(/\x1b\[[0-9;]*m/g, ""));
}

describe("tool row", () => {
  test("OneLine cuts at the width instead of wrapping", () => {
    assert.deepEqual(plain(new OneLine("abcdefghij"), 6), ["abc..."]);
  });

  test("OneLine leaves a row that fits untouched", () => {
    assert.deepEqual(plain(new OneLine("abc"), 10), ["abc"]);
  });

  test("firstLine keeps the first trimmed line of a multi-line value", () => {
    assert.equal(firstLine("  a b  \nc"), "a b");
    assert.equal(firstLine(""), "");
  });

  test("a header names the tool and the id it acts on", () => {
    assert.equal(
      toolRowHeader("subagent", "review-auth", theme),
      "subagent review-auth",
    );
    assert.equal(
      toolRowHeader("subagent_status", undefined, theme),
      "subagent_status",
    );
  });

  test("expanded arguments indent each value under its key", () => {
    assert.deepEqual(expandedArgs({ id: "x", command: "a\nb" }, theme), [
      "  id: x",
      "  command: a",
      "    b",
    ]);
  });

  test("a result's text parts are joined and images skipped", () => {
    const result = {
      content: [
        { type: "text", text: "first" },
        { type: "image", data: "AAAA", mimeType: "image/png" },
        { type: "text", text: "second" },
      ],
      details: {},
    };

    assert.equal(resultText(result), "first\nsecond");
  });
});
