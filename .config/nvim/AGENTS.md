# AGENTS.md

Instructions for AI coding agents working in this Neovim configuration repository.

## Build / Lint / Test

```bash
# Check formatting (required before submitting changes)
make format-check

# Auto-fix formatting
make format

# Lint all Lua files (must pass with 0 warnings, 0 errors)
make lint

# Run both format-check and lint
make
```

This is a Neovim config, not a standalone application. There is no build step, no test suite, and no CI/CD pipeline. To verify changes work, restart Neovim and check `:messages` for errors.

## Project Structure

```
lua/my/
  core/          # Core config (opts, keymaps, autocmds, pack, lsp, etc.)
  pack/          # Plugin specs + resources
    specs/start/ # Plugins loaded immediately
    specs/opt/   # Plugins loaded lazily
    res/         # Per-plugin resources (snippets, DAP configs, test strategies)
  plugin/        # Custom built-in plugins (winbar, im, session, etc.)
  utils/         # Shared utility modules (fs, hl, lsp, str, load, etc.)
```

Entry point: `init.lua` (at repo root). All Lua code lives under `lua/my/`.

## Code Style

### Lua runtime

Target: **LuaJIT** (Neovim's embedded runtime). Do not use Lua 5.2+ features (`goto`, `_ENV`, bit32, etc.).

### Module convention

Always return a table from a Lua file. Never return a bare function.

```lua
-- Bad
return function() end

-- Good
local M = {}
function M.foo() end
return M
```

### Plugin specs

Plugin spec files under `lua/my/pack/specs/{start,opt}/` return a single table:

```lua
---@type my.pack.spec
return {
  src = 'https://github.com/author/plugin.nvim',
  data = {
    deps = { ... },        -- other plugin src URLs
    keys = { ... },        -- keymaps to trigger lazy load
    cmds = { ... },        -- commands to trigger lazy load
    events = { ... },      -- events to trigger lazy load
    init = function(spec, path) end,   -- runs at startup
    preload = function() end,          -- runs before plugin loads
    postload = function() end,         -- runs after plugin loads
  },
}
```

### `init.lua` entry points

Submodules use `init.lua` as the entry point. This file `require()`s sibling modules and returns a table with the public API (often just a `setup()` function).

```lua
-- lua/my/plugin/foo/init.lua
local configs = require('my.plugin.foo.configs')
local utils = require('my.plugin.foo.utils')

local function setup(opts)
  -- ...
end

return { setup = setup }
```

### Resource files

Non-code resource files (snippets, DAP configs, test strategies, projectionist configs) live under `lua/my/pack/res/`, organized by the plugin they serve. These files return plain Lua tables -- they do NOT define M modules.

### Lazy-loading

Use `require('my.utils.load')` helpers to defer loading. Do NOT call `require()` for heavy modules at startup unless they are in `core/` or `start/` specs.

```lua
local load = require('my.utils.load')
load.on_events('FileType', 'my.core.treesitter')  -- lazy load on event
load.on_cmds('MyCommand', 'my.module')            -- lazy load on command
load.on_keys('<Leader>x', 'my.module')             -- lazy load on key
```

### Backend auto-detection pattern

When a plugin needs platform-specific backends (e.g., `my.plugin.im`), use a `backends/` subdirectory with:
- `backends/init.lua` -- defines a base class and a `detect()` function that discovers and instantiates available backends
- `backends/<name>.lua` -- each backend, returning a class table with a `:new()` constructor

### Class pattern

Define classes with `__index = self` and a `:new()` constructor using `setmetatable(..., self)`. Return the class as a named field: `{ ClassName = ClassName }`.

```lua
local Foo = {}
Foo.__index = Foo

function Foo:new()
  return setmetatable({}, self)
end

function Foo:method()
end

return { Foo = Foo }
```

Always use `:` for both definition and invocation of methods. If `self` is unused, suppress the luacheck warning:

```lua
function Foo:detect() -- luacheck: no unused args
```

### Types

Use LuaLS annotations on all module tables and functions:

```lua
---@class my.utils.fs
local M = {}

---Read file contents
---@param path string
---@return string?
function M.read_file(path)
end
```

### Naming conventions

- Module paths: `my.<category>.<name>` (e.g., `my.utils.fs`, `my.plugin.winbar`)
- Local variables: `snake_case`
- Functions: `snake_case`
- Constants: `snake_case` (no ALL_CAPS)
- Augroup names: `my.<plugin>` or `my.<plugin>.<feature>` (e.g., `my.oil`, `my.winbar`)
- Private helpers: no underscore prefix convention; use `local function` scope

### Error handling

- Use `pcall()` (or `vim.npcall()`) for operations that may fail
- Use `vim.notify(msg, vim.log.levels.WARN)` for user-facing warnings
- Check `vim.api.nvim_buf_is_valid(buf)` and `vim.api.nvim_win_is_valid(win)` before operating on buffers/windows
- Use `vim.schedule_wrap()` for callbacks that touch buffer/window state from async contexts

### Formatting

- Indent: 2 spaces (no tabs)
- Max line width: 79 columns
- Quotes: single quotes preferred (`AutoPreferSingle`)
- Use `-- stylua: ignore start` / `-- stylua: ignore end` blocks for deliberate alignment (e.g., keymap tables)
- End files with a trailing newline (LF)

### Linting

Run `luacheck -q .` before completing work. The `.luacheckrc` configures:
- Standard: `luajit`
- Global: `vim`
- Max line length: disabled (stylua handles this)

### Dependencies

Do not add new plugin dependencies without clear justification. Plugin specs reference source repos via HTTPS URLs; lockfile is `nvim-pack-lock.json`. The project targets Neovim nightly (0.13+). Always check `nvim-version.txt` before using bleeding-edge APIs.
