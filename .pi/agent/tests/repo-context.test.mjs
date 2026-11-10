import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

// The extension reads HOME and the agent dir when it loads, so point both at a
// throwaway directory first. Real projects and trust decisions stay untouched.
const root = realpathSync(mkdtempSync(join(tmpdir(), "repo-context-test-")));
process.env.HOME = join(root, "home");
process.env.PI_CODING_AGENT_DIR = join(root, "agent");
mkdirSync(process.env.HOME);
mkdirSync(process.env.PI_CODING_AGENT_DIR);

const { default: repoContext } = await import("../extensions/repo-context.ts");

/** Create a directory with an `AGENTS.md`, and optionally a project skill. */
function makeRepo(name, { skill } = {}) {
  const dir = join(root, name);
  mkdirSync(dir);
  writeFileSync(join(dir, "AGENTS.md"), `# ${name} rules`);
  if (skill) {
    const skillDir = join(dir, ".agents", "skills", skill);
    mkdirSync(skillDir, { recursive: true });
    writeFileSync(
      join(skillDir, "SKILL.md"),
      `---\nname: ${skill}\ndescription: Does ${skill} things.\n---\n`,
    );
  }
  return dir;
}

/** Load the extension with a fake `pi`; Pi itself started in `cwd`. */
function setup(cwd = root) {
  const hooks = new Map();
  const reminders = [];
  repoContext({
    registerMessageRenderer() {},
    on: (name, handler) => hooks.set(name, handler),
    sendMessage: (message) => reminders.push(message.content),
  });
  const ctx = { cwd, ui: { notify() {} } };
  const toolCall = (toolName, path) =>
    hooks.get("tool_call")({ toolName, input: { path } }, ctx);
  const startAgent = (contextFiles = [], skills = []) =>
    hooks.get("before_agent_start")({
      systemPromptOptions: { contextFiles, skills },
    });
  return { hooks, reminders, toolCall, startAgent };
}

test("reading files in another repo sends no reminder", async () => {
  const repo = makeRepo("read-repo");
  const { reminders, toolCall } = setup();

  for (const tool of ["read", "grep", "find", "ls"]) {
    assert.equal(await toolCall(tool, join(repo, "a.ts")), undefined);
  }

  assert.equal(reminders.length, 0);
});

test("the first write into another repo is blocked until the agent sees its rules", async () => {
  const repo = makeRepo("write-repo");
  const { reminders, toolCall } = setup();

  const first = await toolCall("write", join(repo, "a.ts"));
  const retry = await toolCall("write", join(repo, "a.ts"));

  assert.equal(first.block, true);
  assert.equal(retry, undefined);
  assert.equal(reminders.length, 1);
  assert.ok(reminders[0].includes(join(repo, "AGENTS.md")));
});

test("each repo is announced only once", async () => {
  const repo = makeRepo("once-repo");
  const { reminders, toolCall } = setup();

  await toolCall("write", join(repo, "a.ts"));
  await toolCall("edit", join(repo, "b.ts"));

  assert.equal(reminders.length, 1);
});

test("files Pi already loaded at startup are not announced", async () => {
  const repo = makeRepo("loaded-repo");
  const { reminders, toolCall, startAgent } = setup(repo);
  startAgent([{ path: join(repo, "AGENTS.md"), content: "" }]);

  await toolCall("write", join(repo, "a.ts"));

  assert.equal(reminders.length, 0);
});

test("relative paths are resolved from Pi's working directory", async () => {
  const repo = makeRepo("relative-repo");
  const { reminders, toolCall } = setup(root);

  await toolCall("write", "relative-repo/a.ts");

  assert.ok(reminders[0].includes(join(repo, "AGENTS.md")));
});

test("compaction lets the agent see a repo's rules again", async () => {
  const repo = makeRepo("compact-repo");
  const { hooks, reminders, toolCall } = setup();

  await toolCall("write", join(repo, "a.ts"));
  hooks.get("session_compact")({});
  await toolCall("write", join(repo, "a.ts"));

  assert.equal(reminders.length, 2);
});

test("project skills are listed only when the user trusted the repo", async () => {
  const untrusted = makeRepo("untrusted-repo", { skill: "lint-fix" });
  const { reminders, toolCall } = setup();

  await toolCall("write", join(untrusted, "a.ts"));

  // AGENTS.md is always announced; the untrusted skill must not be.
  assert.ok(reminders[0].includes("AGENTS.md"));
  assert.ok(!reminders[0].includes("lint-fix"));
});

test("non-file tools never trigger a reminder", async () => {
  const repo = makeRepo("bash-repo");
  const { reminders, hooks } = setup();

  await hooks.get("tool_call")(
    { toolName: "bash", input: { command: `cat ${repo}/a.ts` } },
    { cwd: root, ui: { notify() {} } },
  );

  assert.equal(reminders.length, 0);
});

test("a write right after a read in the same reply is still blocked", async () => {
  const repo = makeRepo("batch-repo");
  const { toolCall } = setup();

  await toolCall("read", join(repo, "a.ts"));
  const write = await toolCall("write", join(repo, "a.ts"));

  assert.equal(write?.block, true);
});
