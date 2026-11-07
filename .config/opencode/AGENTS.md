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
  names, and command names in backticks (e.g. `\r\n`, `main()`, `$DOT_DIR`).

## Markdown

- Always add a blank line after each markdown heading (`#`, `##`, `###`, etc.)
  when writing to .md files, unless the heading is the last line of the
  document.
- Do NOT number markdown headings (e.g. `## 1. Foo` or `### 2. Bar`). Use plain
  headings like `## Foo` or `### Bar` instead.

## Code style

- Do not use `else` or `elseif` after a branch that unconditionally returns.
  Use a separate `if` instead.
- Prefer early returns over lengthy `if`-`else` structures.
- Keep imports/includes at the top of the file. Avoid lazy, inline, or
  conditional imports unless they are genuinely required.
- Keep error handling simple. Do not add unnecessary `try`-`catch` blocks,
  fallback logic, or defensive recovery for unexpected states; just let crash
  if unexpected error occurs.
