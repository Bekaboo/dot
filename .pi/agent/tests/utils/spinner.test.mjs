import assert from "node:assert/strict";
import test, { describe } from "node:test";

import { Spinner, SPINNER_INTERVAL_MS } from "../../extensions/utils/spinner.ts";

const plainTheme = { fg: (_color, text) => text };
const BRAILLE = /^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]$/;

describe("spinner", () => {
  test("marks finished states with their glyphs and running with a frame", () => {
    const spinner = new Spinner(() => {});
    assert.match(spinner.marker("running", plainTheme), BRAILLE);
    assert.equal(spinner.marker("done", plainTheme), "✓");
    assert.equal(spinner.marker("failed", plainTheme), "✗");
    assert.equal(spinner.marker("timeout", plainTheme), "⧖");
    assert.equal(spinner.marker("killed", plainTheme), "·");
  });

  test("animates only while something runs, and stops when told", (t) => {
    t.mock.timers.enable({ apis: ["setInterval"] });
    let renders = 0;
    const spinner = new Spinner(() => renders++);
    const first = spinner.marker("running", plainTheme);

    spinner.sync(false);
    t.mock.timers.tick(SPINNER_INTERVAL_MS * 10);
    assert.equal(renders, 0, "nothing running, nothing to animate");

    spinner.sync(true);
    spinner.sync(true);
    t.mock.timers.tick(SPINNER_INTERVAL_MS);
    assert.equal(renders, 1, "a second sync does not start a second animation");
    assert.notEqual(spinner.marker("running", plainTheme), first);

    spinner.sync(false);
    t.mock.timers.tick(SPINNER_INTERVAL_MS * 10);
    assert.equal(renders, 1, "the animation stops once nothing runs");

    spinner.sync(true);
    spinner.stop();
    t.mock.timers.tick(SPINNER_INTERVAL_MS * 10);
    assert.equal(renders, 1, "stop ends the animation");
  });
});
