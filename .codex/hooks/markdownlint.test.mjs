import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const hookPath = "/home/zeng/.codex/hooks/markdownlint.mjs";
const directories = [];

afterEach(() => {
  for (const directory of directories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

function fixture(name, content) {
  const cwd = mkdtempSync(join(tmpdir(), "codex-md-lint-"));
  directories.push(cwd);
  writeFileSync(join(cwd, name), content);
  return cwd;
}

function runHook(cwd, toolInput) {
  const inputPath = join(cwd, "hook-input.json");
  writeFileSync(inputPath, JSON.stringify({ cwd, tool_input: toolInput }));
  const result = Bun.spawnSync(["node", hookPath], {
    stdin: Bun.file(inputPath),
    stdout: "pipe",
    stderr: "pipe",
  });
  return {
    status: result.exitCode,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  };
}

describe("Markdown PostToolUse hook", () => {
  test("fixes a relative Markdown path and reports context", () => {
    const cwd = fixture("bad.md", "### 2. Bad\nBody.\n");
    const result = runHook(cwd, { command: "*** Update File: bad.md" });

    expect(result.status).toBe(0);
    expect(readFileSync(join(cwd, "bad.md"), "utf8")).toBe(
      "### Bad\n\nBody.\n",
    );
    const response = JSON.parse(result.stdout);
    expect(response.hookSpecificOutput.hookEventName).toBe("PostToolUse");
    expect(response.hookSpecificOutput.additionalContext).toContain("bad.md");
  });

  test("is silent when Markdown is already clean", () => {
    const cwd = fixture("clean.md", "### Clean\n\nBody.\n");
    const result = runHook(cwd, { command: "*** Update File: clean.md" });

    expect(result.status).toBe(0);
    expect(result.stdout).toBe("");
  });

  test("ignores deleted, missing, and non-Markdown paths", () => {
    const cwd = fixture("bad.txt", "### 2. Bad\nBody.\n");
    const patch = [
      "*** Delete File: gone.md",
      "*** Update File: missing.md",
      "*** Update File: bad.txt",
    ].join("\n");
    const result = runHook(cwd, { command: patch });

    expect(result.status).toBe(0);
    expect(result.stdout).toBe("");
    expect(readFileSync(join(cwd, "bad.txt"), "utf8")).toBe(
      "### 2. Bad\nBody.\n",
    );
  });

  test.each(["file_path", "filePath", "path"])(
    "fixes Markdown from the %s field",
    (field) => {
      const cwd = fixture(`${field}.md`, "### 2. Bad\nBody.\n");
      const result = runHook(cwd, { [field]: `${field}.md` });

      expect(result.status).toBe(0);
      expect(readFileSync(join(cwd, `${field}.md`), "utf8")).toBe(
        "### Bad\n\nBody.\n",
      );
      expect(
        JSON.parse(result.stdout).hookSpecificOutput.additionalContext,
      ).toContain(`${field}.md`);
    },
  );
});
