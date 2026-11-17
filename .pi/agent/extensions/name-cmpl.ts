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
 */

import { homedir } from "node:os";
import { sep } from "node:path";

import {
  type ExtensionAPI,
  SessionManager,
} from "@earendil-works/pi-coding-agent";

import {
  type AutocompleteItem,
  type AutocompleteProvider,
  type AutocompleteSuggestions,
  fuzzyFilter,
} from "@earendil-works/pi-tui";

/** A `/name` line at the start of the message, capturing the argument typed so far. */
const NAME_ARGUMENT_PATTERN = /^\s*\/name\s+([^\n]*)$/;

const MAX_SUGGESTIONS = 20;

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
      return { prefix, items: formatColumns(rows) };
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

export default function (pi: ExtensionAPI): void {
  pi.on("session_start", (_event, ctx) => {
    ctx.ui.addAutocompleteProvider((current) => createProvider(current));
  });
}
