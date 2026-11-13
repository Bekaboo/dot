import assert from "node:assert/strict";
import test, { describe } from "node:test";

import vimRuler from "../extensions/vim-ruler.ts";

const plainTheme = { fg: (_color, text) => text };

/**
 * Install the footer and return it.
 *
 * @param scroll - Transcript scroll state, or undefined for no scroll view.
 * @param options - Footer inputs: TUI mode, git branch, extension statuses.
 */
function setupFooter(
  scroll,
  { mode = "fullscreen", branch, statuses = [] } = {},
) {
  const hooks = new Map();
  vimRuler({ on: (name, handler) => hooks.set(name, handler) });

  let factory;
  const ctx = {
    cwd: "~/repo",
    model: { id: "model-x" },
    ui: { setFooter: (create) => (factory = create) },
  };
  hooks.get("session_start")({}, ctx);

  const tui = {
    mode,
    requestRender() {},
    ...(scroll && { getPrimaryScrollView: () => scroll }),
  };
  const footerData = {
    getGitBranch: () => branch,
    getExtensionStatuses: () => new Map(statuses),
    onBranchChange: () => () => {},
  };
  return factory(tui, plainTheme, footerData);
}

/** Render one footer frame as trimmed lines. */
function render(footer, width = 60) {
  return footer.render(width).map((line) => line.trimEnd());
}

/** Return the ruler at the end of the footer's first line. */
function ruler(scroll) {
  return render(setupFooter(scroll))[0].split(" ").at(-1);
}

const scroll = (scrollTop, isFollowingEnd = false) => ({
  scrollTop,
  contentHeight: 300,
  viewportHeight: 100,
  isFollowingEnd,
});

describe("vim-ruler", () => {
  test("the ruler shows All when the transcript fits on screen", () => {
    assert.equal(
      ruler({ scrollTop: 0, contentHeight: 50, viewportHeight: 100 }),
      "All",
    );
  });

  test("the ruler shows Top, a percentage, and Bot while scrolling", () => {
    assert.equal(ruler(scroll(0)), "Top");
    assert.equal(ruler(scroll(100)), "50%");
    assert.equal(ruler(scroll(200)), "Bot");
  });

  test("the ruler shows Bot while following new output", () => {
    assert.equal(ruler(scroll(150, true)), "Bot");
  });

  test("the footer hides the ruler outside fullscreen mode", () => {
    const footer = setupFooter(scroll(100), { mode: "inline" });

    assert.match(render(footer)[0], /model-x$/);
  });

  test("every footer line fits the terminal width", () => {
    const footer = setupFooter(scroll(100), {
      branch: "a-very-long-branch-name",
      statuses: [["a", "x".repeat(100)]],
    });

    for (const line of footer.render(20)) {
      assert.ok(line.replace(/\x1b\[[0-9;]*m/g, "").length <= 20, line);
    }
  });
});
