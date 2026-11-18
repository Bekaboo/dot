/**
 * Fuzzy completion for the built-in `/name` command's argument.
 *
 * Pi completes command arguments through each command's
 * `getArgumentCompletions`, but `/name` is a built-in interactive command and
 * has none. This extension stacks an autocomplete provider on Pi's combined
 * slash-command/path provider: on a `/name <partial>` editor line it suggests
 * the display names of existing sessions, and delegates every other request
 * untouched. Names come from `SessionManager.listAll`, so the suggestions
 * match the `/resume` picker and span every working directory.
 *
 * `listAll` reads all session files, so the result is cached for
 * `SESSIONS_CACHE_TTL_MS` and shared by concurrent requests; typing the
 * argument triggers one scan per TTL, not one per keystroke.
 *
 * The menu opens without a highlighted entry, so Enter submits the argument
 * that was typed and `tui.select.up`/`tui.select.down` start the selection.
 */

import { homedir } from "node:os";
import { sep } from "node:path";

import {
  CustomEditor,
  type ExtensionAPI,
  type KeybindingsManager,
  SessionManager,
} from "@earendil-works/pi-coding-agent";

import {
  type AutocompleteItem,
  type AutocompleteProvider,
  type AutocompleteSuggestions,
  type EditorTheme,
  fuzzyFilter,
  type SelectList,
  type TUI,
} from "@earendil-works/pi-tui";

/** A `/name` line at the start of the message, capturing the argument typed so far. */
const NAME_ARGUMENT_PATTERN = /^\s*\/name\s+([^\n]*)$/;

const MAX_SUGGESTIONS = 20;

/** Selection index for a menu with no highlighted entry; `SelectList` starts at 0. */
const NO_SELECTION = -1;

/** Marks suggestion arrays built here, so the editor can recognise its menu. */
const NAME_SUGGESTIONS: unique symbol = Symbol("name-completion-suggestions");

/** Name suggestions, tagged for `NameCompletionEditor`. */
type NameSuggestions = AutocompleteItem[] & { [NAME_SUGGESTIONS]?: true };

const SESSIONS_CACHE_TTL_MS = 30_000;

const MINUTE_MS = 60_000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;

interface NamedSession {
  name: string;
  cwd: string;
  modified: Date;
}

let sessionsCache: { loadedAt: number; sessions: NamedSession[] } | undefined;
let sessionsLoad: Promise<NamedSession[]> | undefined;

/**
 * Load named sessions, deduplicated by name and ordered most recently active
 * first (`SessionManager.listAll` sorts by modification time).
 *
 * Concurrent callers share one scan; a rejected scan is not cached, so the
 * next completion retries instead of pinning a transient failure.
 */
function loadNamedSessions(): Promise<NamedSession[]> {
  sessionsLoad ??= SessionManager.listAll()
    .then((infos) => {
      const byName = new Map<string, NamedSession>();
      for (const info of infos) {
        if (info.name && !byName.has(info.name)) {
          byName.set(info.name, {
            name: info.name,
            cwd: info.cwd,
            modified: info.modified,
          });
        }
      }
      sessionsCache = { loadedAt: Date.now(), sessions: [...byName.values()] };
      return sessionsCache.sessions;
    })
    .finally(() => {
      sessionsLoad = undefined;
    });
  return sessionsLoad;
}

/** Return the cached session list while fresh, otherwise start a new scan. */
function namedSessions(): Promise<NamedSession[]> {
  if (
    sessionsCache &&
    Date.now() - sessionsCache.loadedAt < SESSIONS_CACHE_TTL_MS
  ) {
    return Promise.resolve(sessionsCache.sessions);
  }
  return loadNamedSessions();
}

/** Return the text after `/name ` when the cursor sits on a `/name` line. */
function extractNamePrefix(
  lines: string[],
  cursorLine: number,
  cursorCol: number,
): string | undefined {
  if (cursorLine !== 0) return undefined;
  const match = (lines[0] ?? "")
    .slice(0, cursorCol)
    .match(NAME_ARGUMENT_PATTERN);
  return match?.[1];
}

/** Shorten a home-directory path for display, keeping other paths absolute. */
function displayCwd(cwd: string): string {
  const home = homedir();
  if (cwd === home) return "~";
  if (cwd.startsWith(`${home}${sep}`)) return `~${cwd.slice(home.length)}`;
  return cwd;
}

/** Describe how long ago a session was last active. */
function formatAge(ageMs: number): string {
  if (ageMs < HOUR_MS)
    return `${Math.max(1, Math.floor(ageMs / MINUTE_MS))}m ago`;
  if (ageMs < DAY_MS) return `${Math.floor(ageMs / HOUR_MS)}h ago`;
  return `${Math.floor(ageMs / DAY_MS)}d ago`;
}

/** Right-align the age so the "ago" suffix and the directory column line up. */
function formatColumns(
  rows: { session: NamedSession; age: string }[],
): AutocompleteItem[] {
  const ageWidth = rows.reduce(
    (width, row) => Math.max(width, row.age.length),
    0,
  );
  return rows.map(({ session, age }) => ({
    value: session.name,
    label: session.name,
    description: `${age.padStart(ageWidth)}  ${displayCwd(session.cwd)}`,
  }));
}

/**
 * Wrap Pi's provider with `/name` argument completion.
 *
 * The returned prefix is the argument text only; the base provider's
 * `applyCompletion` replaces exactly that token, so the command and the spaces
 * after it stay in place. Items are suggested names only, matching what
 * `handleNameCommand` accepts as the argument.
 */
function createProvider(current: AutocompleteProvider): AutocompleteProvider {
  return {
    async getSuggestions(
      lines,
      cursorLine,
      cursorCol,
      options,
    ): Promise<AutocompleteSuggestions | null> {
      const prefix = extractNamePrefix(lines, cursorLine, cursorCol);
      if (prefix === undefined) {
        return current.getSuggestions(lines, cursorLine, cursorCol, options);
      }

      const sessions = await namedSessions();
      if (options.signal.aborted) {
        return current.getSuggestions(lines, cursorLine, cursorCol, options);
      }

      const query = prefix.trim();
      const matched = query
        ? fuzzyFilter(sessions, query, (session) => session.name)
        : sessions;
      if (matched.length === 0) {
        return current.getSuggestions(lines, cursorLine, cursorCol, options);
      }

      const now = Date.now();
      const rows = matched.slice(0, MAX_SUGGESTIONS).map((session) => ({
        session,
        age: formatAge(now - session.modified.getTime()),
      }));
      const items: NameSuggestions = formatColumns(rows);
      items[NAME_SUGGESTIONS] = true;
      return { prefix, items };
    },

    applyCompletion(lines, cursorLine, cursorCol, item, prefix) {
      return current.applyCompletion(
        lines,
        cursorLine,
        cursorCol,
        item,
        prefix,
      );
    },

    shouldTriggerFileCompletion(lines, cursorLine, cursorCol) {
      return (
        current.shouldTriggerFileCompletion?.(lines, cursorLine, cursorCol) ??
        true
      );
    },
  };
}

/**
 * Editor that keeps the `/name` menu free of an initial selection.
 *
 * Pi's editor highlights the first autocomplete entry as soon as a menu opens
 * and Enter applies that entry before submitting, so `/name <typed>` became
 * `/name <first session name>`. Here the menu opens with nothing highlighted,
 * which leaves Enter submitting the typed argument, and `tui.select.up` /
 * `tui.select.down` start an explicit selection. While nothing is selected Tab
 * does nothing; once an entry is selected, Tab and Enter apply it.
 *
 * A menu is recognised by the marker on the suggestion array built in
 * `getSuggestions`, not by the editor text, so a menu that the wrapped provider
 * returned for the same `/name` line (for example a Tab-triggered path menu)
 * keeps its normal pre-selection.
 *
 * `autocompleteList`, `SelectList.items` and `SelectList.selectedIndex` are
 * private in the pi-tui typings and no public option controls the initial
 * selection, so they are reached through narrowed casts. Drop the casts once
 * pi-tui exposes a way to open a menu unselected.
 */
class NameCompletionEditor extends CustomEditor {
  // Named apart from CustomEditor's own `keybindings` field to avoid shadowing it.
  private readonly selectKeybindings: KeybindingsManager;
  private nameMenu?: SelectList;

  constructor(tui: TUI, theme: EditorTheme, keybindings: KeybindingsManager) {
    super(tui, theme, keybindings, { embedWorkingStatus: true });
    this.selectKeybindings = keybindings;
  }

  render(width: number): string[] {
    this.prepareNameMenu();
    return super.render(width);
  }

  /**
   * Handle the first selection key on a freshly opened `/name` menu.
   *
   * Down picks the first entry. Up also starts at the first entry and lets
   * `SelectList` wrap, so both ends of the list stay one press away.
   */
  handleInput(data: string): void {
    const list = this.prepareNameMenu();
    if (list && list.getSelectedItem() === null) {
      if (this.selectKeybindings.matches(data, "tui.select.down")) {
        list.setSelectedIndex(0);
        return;
      }
      if (this.selectKeybindings.matches(data, "tui.select.up")) {
        list.setSelectedIndex(0);
        list.handleInput(data);
        return;
      }
    }
    super.handleInput(data);
  }

  /**
   * Return the completion list while the open menu holds this extension's
   * suggestions, clearing the pre-selection of a list that was just rebuilt
   * for the current keystroke.
   *
   * @returns The menu's list for a name suggestion set, otherwise undefined
   *   for other menus and for a closed menu.
   */
  private prepareNameMenu(): SelectList | undefined {
    if (!this.isShowingAutocomplete()) {
      this.nameMenu = undefined;
      return undefined;
    }
    const list = (this as unknown as { autocompleteList?: SelectList })
      .autocompleteList;
    if (!list) return undefined;
    if (list === this.nameMenu) return list;
    const items = (list as unknown as { items?: NameSuggestions }).items;
    if (!items?.[NAME_SUGGESTIONS]) {
      this.nameMenu = undefined;
      return undefined;
    }
    (list as unknown as { selectedIndex: number }).selectedIndex = NO_SELECTION;
    this.nameMenu = list;
    return list;
  }
}

export default function (pi: ExtensionAPI): void {
  pi.on("session_start", (_event, ctx) => {
    // The app drops autocomplete wrappers on every session switch and reload
    // (`resetExtensionUI`), so the provider has to be added again each time.
    ctx.ui.addAutocompleteProvider((current) => createProvider(current));
    // Another extension's editor already owns the input; replacing it would
    // lose that editor, so the safer default behaviour stays in place.
    if (ctx.ui.getEditorComponent()) return;
    ctx.ui.setEditorComponent(
      (tui, theme, keybindings) =>
        new NameCompletionEditor(tui, theme, keybindings),
    );
  });
}
