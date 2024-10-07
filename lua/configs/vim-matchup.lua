vim.g.matchup_matchparen_deferred = 1 -- improve scrolling performance
vim.g.matchup_matchparen_deferred_show_delay = 16
vim.g.matchup_matchparen_deferred_hide_delay = 16
vim.g.matchup_matchparen_offscreen = {} -- don't show offscreen matches
vim.g.matchup_matchparen_end_sign = require('utils.static').icons.ArrowLeft

-- Disabled for performance reasons
-- Treesitter integration becomes quite slow in large C files (over 5000 lines)
--
-- Check the flamegraph:
-- 1. `:lua require('jit.p').start('10,i1,s,m0,G', '/tmp/output.log')`
-- 2. Start typing in a big C file
-- 3. Stop typing
-- 4. `:lua require('jit.p').stop()`
-- 5. From the command line, run `flamegraph.pl /tmp/output.log > flamegraph.svg`
-- 6. Open the svg in a browser

-- local has_nvim_ts_cfg, nvim_ts_cfg = pcall(require, 'nvim-treesitter.configs')
-- if has_nvim_ts_cfg then
--   ---@diagnostic disable-next-line: missing-fields
--   nvim_ts_cfg.setup({
--     matchup = {
--       enable = true,
--       disable_virtual_text = true,
--     },
--   })
-- end
