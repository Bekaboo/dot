import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const event = JSON.parse(readFileSync(0, "utf8"));
const toolInput = event.tool_input ?? {};
const patch = typeof toolInput.command === "string" ? toolInput.command : "";
const directPaths = [
  toolInput.file_path,
  toolInput.filePath,
  toolInput.path,
].filter((path) => typeof path === "string");
const patchPaths = [...patch.matchAll(/^\*\*\* (?:Add|Update) File: (.+)$/gm)].map(
  (match) => match[1].trim(),
);
const paths = [...new Set([...directPaths, ...patchPaths])]
  .filter((path) => path.endsWith(".md"))
  .map((path) => (isAbsolute(path) ? path : resolve(event.cwd, path)))
  .filter(existsSync);

if (paths.length === 0) process.exit(0);

const before = new Map(paths.map((path) => [path, readFileSync(path, "utf8")]));
const result = spawnSync(
  "markdownlint-cli2",
  ["--config", resolve(homedir(), ".markdownlint-cli2.cjs"), "--fix", ...paths],
  { encoding: "utf8" },
);
const fixed = paths.filter((path) => before.get(path) !== readFileSync(path, "utf8"));

if (result.status !== 0) {
  console.log(
    JSON.stringify({
      decision: "block",
      reason: `markdownlint-cli2 found unresolved issues:\n${result.stderr || result.stdout}`,
    }),
  );
} else if (fixed.length > 0) {
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: `markdownlint-cli2 automatically fixed: ${fixed.join(", ")}. Review the changes.`,
      },
    }),
  );
}
