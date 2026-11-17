import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test, { describe } from "node:test";

// SessionManager reads the agent dir on each listing, so point HOME and the
// agent dir at a throwaway tree before importing the extension.
const root = realpathSync(mkdtempSync(join(tmpdir(), "name-cmpl-test-")));
process.env.HOME = join(root, "home");
process.env.PI_CODING_AGENT_DIR = join(root, "agent");
mkdirSync(process.env.HOME);
mkdirSync(process.env.PI_CODING_AGENT_DIR);

const sessionsDir = join(
  process.env.PI_CODING_AGENT_DIR,
  "sessions",
  "--projects-demo--",
);
mkdirSync(sessionsDir, { recursive: true });

const MINUTE_MS = 60_000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;

/** Write a minimal valid session file: header plus an optional name entry. */
function writeSession(file, { cwd, name, ageMs }) {
  const timestamp = new Date(Date.now() - ageMs).toISOString();
  const lines = [
    JSON.stringify({ type: "session", version: 3, id: file, timestamp, cwd }),
  ];
  if (name) {
    lines.push(
      JSON.stringify({
        type: "session_info",
        id: `${file}-name`,
        parentId: null,
        timestamp,
        name,
      }),
    );
  }
  writeFileSync(join(sessionsDir, file), `${lines.join("\n")}\n`);
}

// Ages of different widths ("9m ago", "10h ago", "3d ago") so the column
// alignment is actually exercised.
writeSession("auth.jsonl", {
  cwd: "/work/auth-service",
  name: "Refactor auth module",
  ageMs: 3 * DAY_MS,
});
writeSession("parrot.jsonl", {
  cwd: "/work/parrot",
  name: "Pi parrot extension",
  ageMs: 10 * HOUR_MS,
});
writeSession("parrot-cont.jsonl", {
  cwd: "/work/parrot",
  name: "Pi parrot extension cont.",
  ageMs: 9 * MINUTE_MS,
});
writeSession("parrot-old.jsonl", {
  cwd: "/work/parrot-old",
  name: "Pi parrot extension",
  ageMs: 30 * DAY_MS,
});
writeSession("unnamed.jsonl", {
  cwd: "/work/unnamed",
  ageMs: 5 * DAY_MS,
});

const { CombinedAutocompleteProvider } = await import("@earendil-works/pi-tui");
const { default: nameCompletion } = await import("../extensions/name-cmpl.ts");

/** Load the extension and return its wrapper around Pi's combined provider. */
function loadProvider() {
  let wrapProvider;
  nameCompletion({
    on: (name, handler) => {
      if (name !== "session_start") return;
      handler(
        {},
        {
          ui: {
            addAutocompleteProvider: (factory) => {
              wrapProvider = factory;
            },
          },
        },
      );
    },
  });
  return wrapProvider(new CombinedAutocompleteProvider([], root));
}

const provider = loadProvider();
const options = { signal: new AbortController().signal };

function complete(line, cursorCol = line.length) {
  return provider.getSuggestions([line], 0, cursorCol, options);
}

describe("name-cmpl", () => {
  test("fuzzy matches session names for the /name argument", async () => {
    const suggestions = await complete("/name parr");

    assert.equal(suggestions.prefix, "parr");
    assert.deepEqual(suggestions.items.map((item) => item.value).sort(), [
      "Pi parrot extension",
      "Pi parrot extension cont.",
    ]);
  });

  test("matches case-insensitively", async () => {
    const suggestions = await complete("/name REF");

    assert.deepEqual(
      suggestions.items.map((item) => item.value),
      ["Refactor auth module"],
    );
  });

  test("lists every named session for an empty argument", async () => {
    const suggestions = await complete("/name ");

    assert.deepEqual(suggestions.items.map((item) => item.value).sort(), [
      "Pi parrot extension",
      "Pi parrot extension cont.",
      "Refactor auth module",
    ]);
  });

  test("aligns the age and directory columns", async () => {
    const suggestions = await complete("/name ");

    // 9m ago / 10h ago / 3d ago render at different unpadded widths.
    const ageEndColumns = suggestions.items.map((item) =>
      item.description.indexOf("ago"),
    );
    const directoryColumns = suggestions.items.map((item) =>
      item.description.search(/[~/]/),
    );
    assert.equal(new Set(ageEndColumns).size, 1);
    assert.equal(new Set(directoryColumns).size, 1);
  });

  test("deduplicates names, keeping the most recently active session", async () => {
    const suggestions = await complete("/name Pi parrot extension");

    const exact = suggestions.items.filter(
      (item) => item.value === "Pi parrot extension",
    );
    assert.equal(exact.length, 1);
    assert.ok(exact[0].description.endsWith("/work/parrot"));
  });

  test("no matching name leaves the menu closed", async () => {
    assert.equal(await complete("/name zzzz"), null);
  });

  test("applying a suggestion replaces only the argument", () => {
    const lines = ["/name parr"];

    const result = provider.applyCompletion(
      lines,
      0,
      lines[0].length,
      { value: "Pi parrot extension", label: "Pi parrot extension" },
      "parr",
    );

    assert.deepEqual(result.lines, ["/name Pi parrot extension"]);
    assert.equal(result.cursorCol, "/name Pi parrot extension".length);
  });

  test("leaves other input to the wrapped provider", async () => {
    assert.equal(await complete("hello parr"), null);
    assert.equal(await complete("/name"), null);
  });
});
