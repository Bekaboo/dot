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

-- Only the config root is added to 'runtimepath', not its `after` directory,
-- so that `after/ftplugin` and friends do not interfere with the tests.
vim.opt.rtp:prepend(root_dir)
vim.opt.rtp:prepend(plenary_dir)

-- Make test helpers requirable from specs, e.g. `require('helpers')`
package.path = table.concat({
  vim.fs.joinpath(tests_dir, '?.lua'),
  vim.fs.joinpath(tests_dir, '?/init.lua'),
  package.path,
}, ';')
