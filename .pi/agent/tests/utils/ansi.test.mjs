/**
 * Tests for truncation that leaves the enclosing background in place.
 *
 * A tool block and a selected list row paint their background around a whole
 * line, so a cut row must not reset it in the middle of that line.
 */

import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { visibleWidth } from "@earendil-works/pi-tui";
import { truncateKeepingBackground } from "../../extensions/utils/ansi.ts";

/** A full SGR reset, the sequence that would clear an enclosing background. */
const FULL_RESET = /\x1b\[0m/;

/** Styling codes, so a row can be read as the terminal shows it. */
const STYLED = /\x1b\[[0-9;]*m/g;

/** The band a selected row paints around one line. */
const paint = (text) => `\x1b[44m${text}\x1b[49m`;

/** Faint on and off, so a cut mark reads as secondary. */
const FAINT = "\x1b[2m";

describe("truncateKeepingBackground", () => {
  test("a row that fits is returned unchanged", () => {
    const text = "\x1b[31mabc\x1b[39m";

    assert.equal(truncateKeepingBackground(text, 10), text);
    assert.ok(!text.includes(FAINT), text);
  });

  test("a cut row keeps the background under its ellipsis and padding", () => {
    const line = truncateKeepingBackground("\x1b[31mabcdefgh\x1b[39m", 6);

    assert.equal(visibleWidth(line), 6);
    assert.equal(line.replace(STYLED, ""), "abc...");
    // The band opens before the row; nothing inside it may reset everything.
    assert.doesNotMatch(paint(line), FULL_RESET);
  });

  test("a cut mark is faint, so bright text does not end bright", () => {
    const line = truncateKeepingBackground("\x1b[1mabcdefgh\x1b[22m", 6);

    assert.ok(line.includes(`${FAINT}...`), line);
  });

  test("a padded row still fills the width without clearing the band", () => {
    const line = truncateKeepingBackground("abcdefghij", 6, "...", true);

    assert.equal(visibleWidth(line), 6);
    assert.equal(line.replace(STYLED, ""), "abc...");
    assert.doesNotMatch(paint(line), FULL_RESET);
  });
});
