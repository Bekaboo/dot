-- Minimal init for the test suite, run through the `test*` targets in the
-- Makefile, e.g.
--
--   nvim --clean --headless -u tests/minimal_init.lua \
--     +"PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua' }"
--
-- Specs live under `tests/plugin` (builtin plugins), `tests/utils` (utility
-- modules), and `tests/thirdparty`/`tests/e2e` once those exist.

local tests_dir =
  vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
local root_dir = vim.fn.fnamemodify(tests_dir, ':h')

-- plenary provides the busted runner and luassert. It is managed by
-- `vim.pack` like any other third-party plugin of this config, see
-- `nvim-pack-lock.json`.
local plenary_dir =
  vim.fs.joinpath(vim.fn.stdpath('data'), 'site/pack/core/opt/plenary.nvim')
if vim.fn.isdirectory(plenary_dir) == 0 then
  error(
    ('plenary.nvim not found in %s, install plugins first'):format(plenary_dir)
  )
end

vim.o.swapfile = false
-- Don't read or write ShaDa, the busted runner spawns one nvim per spec file
-- and concurrent access to the same ShaDa file makes `:edit` fail with E576
vim.o.shadafile = 'NONE'

-- Keep only the parts of 'runtimepath' that belong to the nvim installation
-- (its runtime and bundled tree-sitter parsers), this config and plenary: the
-- busted runner spawns the spec processes without `--clean`, so the default
-- 'runtimepath' also contains the user's runtime and the `after` directory of
-- this config, whose ftplugins interfere with the specs
local install_dir = vim.fn.fnamemodify(vim.env.VIMRUNTIME, ':h:h:h')
local rtp = { plenary_dir, root_dir }
for _, dir in ipairs(vim.api.nvim_list_runtime_paths()) do
  if vim.startswith(dir, install_dir .. '/') then
    table.insert(rtp, dir)
  end
end
vim.opt.rtp = rtp
-- Don't load packages from the user's data directory either
vim.opt.packpath = {}

-- Make test helpers requirable from specs, e.g. `require('helpers')`
package.path = table.concat({
  vim.fs.joinpath(tests_dir, '?.lua'),
  vim.fs.joinpath(tests_dir, '?/init.lua'),
  package.path,
}, ';')
