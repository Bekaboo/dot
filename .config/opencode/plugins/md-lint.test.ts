import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { MdLintPlugin } from "./md-lint";

const directories: string[] = [];

afterEach(() => {
  for (const directory of directories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

async function setup() {
  const logs: unknown[] = [];
  const plugin = await MdLintPlugin({
    client: { app: { log: async (entry: unknown) => logs.push(entry) } },
  } as never);
  return { hook: plugin["tool.execute.after"]!, logs };
}

function temporaryFile(name: string, content: string) {
  const directory = mkdtempSync(join(tmpdir(), "opencode-md-lint-"));
  directories.push(directory);
  const filePath = join(directory, name);
  writeFileSync(filePath, content);
  return filePath;
}

describe("MdLintPlugin", () => {
  test("fixes malformed Markdown and returns model-visible feedback", async () => {
    const filePath = temporaryFile("bad.md", "## 1. Bad\nBody.\n");
    const { hook, logs } = await setup();
    const output = { title: "Write", output: "Wrote file.", metadata: {} };

    await hook(
      { tool: "write", sessionID: "test", callID: "test", args: { filePath } },
      output,
    );

    expect(readFileSync(filePath, "utf8")).toBe("## Bad\n\nBody.\n");
    expect(output.output).toContain("automatically fixed Markdown formatting");
    expect(logs).toHaveLength(1);
  });

  test("leaves clean Markdown silent", async () => {
    const filePath = temporaryFile("clean.md", "## Clean\n\nBody.\n");
    const { hook, logs } = await setup();
    const output = { title: "Edit", output: "Edit applied.", metadata: {} };

    await hook(
      { tool: "edit", sessionID: "test", callID: "test", args: { filePath } },
      output,
    );

    expect(output.output).toBe("Edit applied.");
    expect(logs).toEqual([]);
  });

  test("ignores non-Markdown files and unrelated tools", async () => {
    const filePath = temporaryFile("bad.txt", "## 1. Bad\nBody.\n");
    const { hook, logs } = await setup();
    const output = { title: "Write", output: "Wrote file.", metadata: {} };

    await hook(
      { tool: "write", sessionID: "test", callID: "test", args: { filePath } },
      output,
    );
    await hook(
      { tool: "read", sessionID: "test", callID: "test", args: { filePath } },
      output,
    );

    expect(readFileSync(filePath, "utf8")).toBe("## 1. Bad\nBody.\n");
    expect(logs).toEqual([]);
  });
});
