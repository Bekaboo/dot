## Shell

- Use normal, reproducible commands for dependency installation and builds.
  Keep standard cache and dependency locations, such as the default
  `PYTHONPATH`, `GOPATH` and `GOCACHE`.
- If a command needs to write to the home directory or change system packages,
  request approval to run the normal command outside the sandbox. Do not
  redirect caches, dependencies, or tool installations to `/tmp` merely to work
  around sandbox restrictions.

## Output

- Do NOT use special/unicode characters that cannot be typed directly on a
  standard keyboard (e.g. →, —, •, «», etc.). Use plain ASCII alternatives
  instead (e.g. `->`, `--`, `*`, `<<>>`).
- Do NOT use markdown bold (`**text**`) in your output, unless truly necessary.
- Always wrap special characters, filenames, variable/function/class/module
  names, and commands in backticks (e.g. `\r\n`, `main()`, `$DOT_DIR`), except
  for pure numbers or digits.

## Markdown

- Always add a blank line after each markdown heading (`#`, `##`, `###`, etc.)
  when writing to .md files, unless the heading is the last line of the
  document.
- Do NOT number markdown headings (e.g. `## 1. Foo` or `### 2. Bar`). Use plain
  headings like `## Foo` or `### Bar` instead.

## Code style

### Clarity and structure

- Keep your code clean, readable and elegant: fewer indents, less nesting,
  clarity over cleverness. If a hack is unavoidable, keep it narrow and
  comment why it exists and when it can go.
- Don't over-engineer: no abstractions or layers for a single call site or a
  hypothetical future, and no flexibility that serves only callers that don't
  exist yet.
- Match the shapes already around you before inventing a new one: the same kind
  of class & function for the same job, the same naming and doc patterns. Read
  sibling files first; if the established shape is genuinely wrong, fix it
  everywhere instead of adding a competing style.
- Remove dead code, unused parameters, debug prints and commented-out blocks.

### Control flow

- Do not use `else` or `elseif` after a branch that unconditionally returns.
  Use a separate `if` instead.
- Prefer early returns over lengthy `if`-`else` structures.
- Prefer a map/table or `switch` over repeated `if`-`else` chains when there
  are genuinely several choices.

### Imports and errors

- Keep imports/includes at the top of the file. Avoid lazy, inline, or
  conditional imports unless they are genuinely required.
- Keep error handling simple. Do not add unnecessary `try`-`catch` blocks,
  fallback logic, or defensive recovery for unexpected states; just let crash
  if unexpected error occurs.

### Documentation and constants

- Write doc comments for non-trivial functions, methods, types, and
  interfaces. Describe the purpose and contract, and use `@param`/`@returns`
  when the signature is not self-explanatory. Match the existing file style.
- Do not use magic numbers. Assign meaningful named constants when the value
  carries domain meaning. Do not invent trivial conversion constants such as
  `MS_PER_SEC = 1000`; use the literal when its meaning is obvious from the
  expression.

## Tests

- Assert the outcome, not the route: the value a caller gets back, the state
  left on disk, the request that leaves the process. Pinning an intermediate
  breaks on refactors that change nothing observable and passes while the
  outcome is wrong.
- Read that outcome the way a consumer would, not the wording, layout or
  ordering the current implementation happens to produce.
- Pin only what is really the contract, such as a documented syntax, wire
  format or stored schema; representation that is merely current does not
  belong in a test.
