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

const {
  CombinedAutocompleteProvider,
  KeybindingsManager,
  SelectList,
  TUI_KEYBINDINGS,
} = await import("@earendil-works/pi-tui");
const { default: nameCompletion } = await import("../extensions/name-cmpl.ts");

/** Load the extension and return its provider wrapper and editor factory. */
function loadExtension() {
  let wrapProvider;
  let editorFactory;
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
            getEditorComponent: () => undefined,
            setEditorComponent: (factory) => {
              editorFactory = factory;
            },
          },
        },
      );
    },
  });
  return {
    provider: wrapProvider(new CombinedAutocompleteProvider([], root)),
    editorFactory,
  };
}

const { provider, editorFactory } = loadExtension();
const options = { signal: new AbortController().signal };

function complete(line, cursorCol = line.length) {
  return provider.getSuggestions([line], 0, cursorCol, options);
}

const identity = (text) => text;
const editorTheme = {
  borderColor: identity,
  selectList: {
    selectedPrefix: identity,
    selectedText: identity,
    description: identity,
    scrollInfo: identity,
    noMatch: identity,
  },
};

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

  test("renders the directory column aligned", async () => {
    const suggestions = await complete("/name ");

    const list = new SelectList(suggestions.items, 10, editorTheme.selectList);
    const directoryColumns = list
      .render(200)
      .map((line) => line.search(/[~/]/));
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

const OTHER_ITEMS = [
  { value: "Alpha session", label: "Alpha session" },
  { value: "Beta session", label: "Beta session" },
  { value: "Gamma session", label: "Gamma session" },
];
const tui = { terminal: { rows: 24 }, requestRender() {} };
const keybindings = new KeybindingsManager(TUI_KEYBINDINGS);

/** Create the extension's editor with the given prompt text. */
function createEditor(line) {
  const editor = editorFactory(tui, editorTheme, keybindings);
  editor.setText(line);
  return editor;
}

/**
 * Open a menu on the editor the way its autocomplete request would.
 *
 * Without `items`, the extension's provider builds them from the editor text.
 * `items` stands in for a menu the wrapped provider returned for the same line.
 */
async function openMenu(editor, items) {
  const line = editor.getText();
  const suggestions = await complete(line);
  editor.autocompleteProvider = provider;
  // A delegated menu still replaces the typed argument, so fall back to it.
  editor.autocompletePrefix =
    suggestions?.prefix ?? line.slice("/name ".length);
  editor.autocompleteList = new SelectList(
    items ?? suggestions.items,
    5,
    editorTheme.selectList,
  );
  editor.autocompleteState = "regular";
  return items ?? suggestions.items;
}

describe("name-cmpl editor", () => {
  test("enter submits the typed argument instead of an entry", async () => {
    const editor = createEditor("/name parr");
    const submitted = [];
    editor.onSubmit = (text) => submitted.push(text);
    await openMenu(editor);

    editor.handleInput("\r");

    assert.deepEqual(submitted, ["/name parr"]);
    assert.equal(editor.isShowingAutocomplete(), false);
  });

  test("opens the menu with no highlighted entry", async () => {
    const editor = createEditor("/name ");
    const items = await openMenu(editor);

    const menu = editor.render(80).filter((line) => line.includes("ago"));
    assert.equal(editor.autocompleteList.getSelectedItem(), null);
    assert.equal(menu.length, items.length);
    assert.ok(menu.every((line) => !line.includes("\u2192")));
  });

  test("down selects the first entry and enter applies it", async () => {
    const editor = createEditor("/name ");
    const items = await openMenu(editor);

    editor.handleInput("\x1b[B");

    assert.equal(
      editor.autocompleteList.getSelectedItem().value,
      items[0].value,
    );
    editor.handleInput("\r");
    assert.equal(editor.getText(), `/name ${items[0].value}`);
  });

  test("up selects the last entry", async () => {
    const editor = createEditor("/name ");
    const items = await openMenu(editor);

    editor.handleInput("\x1b[A");

    assert.equal(
      editor.autocompleteList.getSelectedItem().value,
      items[items.length - 1].value,
    );
  });

  test("a fully typed name is still not pre-selected", async () => {
    const name = "Pi parrot extension";
    const editor = createEditor(`/name ${name}`);
    const submitted = [];
    editor.onSubmit = (text) => submitted.push(text);
    await openMenu(editor);

    editor.render(80);
    assert.equal(editor.autocompleteList.getSelectedItem(), null);
    editor.handleInput("\r");
    assert.deepEqual(submitted, [`/name ${name}`]);
  });

  test("escape closes the menu without submitting", async () => {
    const editor = createEditor("/name ");
    const submitted = [];
    editor.onSubmit = (text) => submitted.push(text);
    await openMenu(editor);

    editor.handleInput("\x1b");

    assert.equal(editor.isShowingAutocomplete(), false);
    assert.deepEqual(submitted, []);
  });

  test("a menu rebuilt for a new argument is unselected again", async () => {
    const editor = createEditor("/name p");
    await openMenu(editor);
    editor.render(80);
    editor.handleInput("\x1b[B");
    assert.ok(editor.autocompleteList.getSelectedItem());

    editor.setText("/name pa");
    await openMenu(editor);
    editor.render(80);

    assert.equal(editor.autocompleteList.getSelectedItem(), null);
  });

  test("keeps the initial selection of menus from the wrapped provider", async () => {
    const editor = createEditor("/name zzzz");
    const submitted = [];
    editor.onSubmit = (text) => submitted.push(text);
    await openMenu(editor, OTHER_ITEMS);

    editor.handleInput("\r");

    assert.deepEqual(submitted, []);
    assert.equal(editor.getText(), `/name ${OTHER_ITEMS[0].value}`);
  });

  test("keeps the initial selection of menus outside /name", () => {
    const editor = createEditor("hello ");
    editor.autocompleteProvider = provider;
    editor.autocompletePrefix = "hello";
    editor.autocompleteList = new SelectList(
      OTHER_ITEMS,
      5,
      editorTheme.selectList,
    );
    editor.autocompleteState = "regular";

    editor.handleInput("\x1b[B");

    assert.equal(
      editor.autocompleteList.getSelectedItem().value,
      OTHER_ITEMS[1].value,
    );
  });
});
