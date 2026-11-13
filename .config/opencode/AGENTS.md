## Coding

- Read sibling files first and match existing shapes, naming, and doc
  patterns. If the established shape is wrong, fix it everywhere instead of
  adding a competing style.
- Clarity over cleverness: minimal nesting and indentation. Keep any
  unavoidable hack narrow, commented with why it exists and when it can go.
- No speculative abstraction: no layers or flexibility for a single call
  site or callers that do not exist yet.
- Delete dead code, unused parameters, debug prints, commented-out blocks.
- Prefer early returns; no `else` after a branch that unconditionally
  returns; prefer a map/table or `switch` over repeated `if`-`else` chains.
- Imports at the top of the file; no lazy, inline, or conditional imports
  unless genuinely required.
- Let unexpected errors crash: no defensive `try`-`catch`, fallbacks, or
  recovery for states that should not occur.
- Doc-comment non-trivial functions, methods, types, and interfaces: purpose
  and contract, `@param`/`@returns` when the signature is not self-explanatory.
- Name constants that carry domain meaning; no magic numbers, but no trivial
  ones either (`MS_PER_SEC = 1000`) when the literal is self-evident.

## Tests

- Assert outcomes, not routes: return values, on-disk state, outgoing
  requests -- not intermediates that refactor away or pass while the
  outcome is wrong.
- Read results as a consumer would, not by current wording, layout, or
  ordering. Pin only real contracts (documented syntax, wire format, stored
  schema), never incidental representation.

## Shell

- Use normal, reproducible install/build commands; keep default cache and
  dependency locations (`PYTHONPATH`, `GOPATH`, `GOCACHE`).
- To write to `$HOME` or change system packages, request approval to run
  outside the sandbox; never redirect caches or installs to `/tmp` to
  work around sandbox limits.

## Evidence

- Every quoted log line, JSON field, test result, error, or artifact needs a
  source: file path (specific searchable phrasing, class/function/variable
  name), or the command that produce the source.

## Output Formatting

- ASCII only: use `->`, `--`, `*`, `<<>>` instead of unicode equivalents.
- No markdown bold unless truly necessary.
- Backtick filenames, identifiers, commands, and special characters (`\r\n`,
  `main()`, `$DOT_DIR`); leave plain numbers bare.
- In `.md` files: blank line after each heading (unless it is the last line),
  and no numbered headings (`## Foo`, not `## 1. Foo`).
