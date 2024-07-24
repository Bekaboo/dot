vim.keymap.set({ 'n', 'x' }, '<Space>', '<Ignore>')
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Multi-window operations
-- stylua: ignore start
vim.keymap.set({ 'x', 'n' }, '<M-W>',      '<C-w>W')
vim.keymap.set({ 'x', 'n' }, '<M-H>',      '<C-w>H')
vim.keymap.set({ 'x', 'n' }, '<M-J>',      '<C-w>J')
vim.keymap.set({ 'x', 'n' }, '<M-K>',      '<C-w>K')
vim.keymap.set({ 'x', 'n' }, '<M-L>',      '<C-w>L')
vim.keymap.set({ 'x', 'n' }, '<M-p>',      '<C-w>p')
vim.keymap.set({ 'x', 'n' }, '<M-r>',      '<C-w>r')
vim.keymap.set({ 'x', 'n' }, '<M-v>',      '<C-w>v')
vim.keymap.set({ 'x', 'n' }, '<M-s>',      '<C-w>s')
vim.keymap.set({ 'x', 'n' }, '<M-x>',      '<C-w>x')
vim.keymap.set({ 'x', 'n' }, '<M-z>',      '<C-w>z')
vim.keymap.set({ 'x', 'n' }, '<M-c>',      '<C-w>c')
vim.keymap.set({ 'x', 'n' }, '<M-q>',      '<C-w>q')
vim.keymap.set({ 'x', 'n' }, '<M-n>',      '<C-w>n')
vim.keymap.set({ 'x', 'n' }, '<M-o>',      '<C-w>o')
vim.keymap.set({ 'x', 'n' }, '<M-t>',      '<C-w>t')
vim.keymap.set({ 'x', 'n' }, '<M-T>',      '<C-w>T')
vim.keymap.set({ 'x', 'n' }, '<M-]>',      '<C-w>]')
vim.keymap.set({ 'x', 'n' }, '<M-^>',      '<C-w>^')
vim.keymap.set({ 'x', 'n' }, '<M-b>',      '<C-w>b')
vim.keymap.set({ 'x', 'n' }, '<M-d>',      '<C-w>d')
vim.keymap.set({ 'x', 'n' }, '<M-f>',      '<C-w>f')
vim.keymap.set({ 'x', 'n' }, '<M-}>',      '<C-w>}')
vim.keymap.set({ 'x', 'n' }, '<M-g>]',     '<C-w>g]')
vim.keymap.set({ 'x', 'n' }, '<M-g>}',     '<C-w>g}')
vim.keymap.set({ 'x', 'n' }, '<M-g>f',     '<C-w>gf')
vim.keymap.set({ 'x', 'n' }, '<M-g>F',     '<C-w>gF')
vim.keymap.set({ 'x', 'n' }, '<M-g>t',     '<C-w>gt')
vim.keymap.set({ 'x', 'n' }, '<M-g>T',     '<C-w>gT')
vim.keymap.set({ 'x', 'n' }, '<M-w>',      '<C-w><C-w>')
vim.keymap.set({ 'x', 'n' }, '<M-h>',      '<C-w><C-h>')
vim.keymap.set({ 'x', 'n' }, '<M-j>',      '<C-w><C-j>')
vim.keymap.set({ 'x', 'n' }, '<M-k>',      '<C-w><C-k>')
vim.keymap.set({ 'x', 'n' }, '<M-l>',      '<C-w><C-l>')
vim.keymap.set({ 'x', 'n' }, '<M-g><M-]>', '<C-w>g<C-]>')
vim.keymap.set({ 'x', 'n' }, '<M-g><Tab>', '<C-w>g<Tab>')

vim.keymap.set({ 'x', 'n' }, '<M-=>', '<C-w>=')
vim.keymap.set({ 'x', 'n' }, '<M-_>', '<C-w>_')
vim.keymap.set({ 'x', 'n' }, '<M-|>', '<C-w>|')
vim.keymap.set({ 'x', 'n' }, '<M-+>', 'v:count ? "<C-w>+" : "2<C-w>+"', { expr = true })
vim.keymap.set({ 'x', 'n' }, '<M-->', 'v:count ? "<C-w>-" : "2<C-w>-"', { expr = true })
vim.keymap.set({ 'x', 'n' }, '<M->>', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w><" : "<C-w>>")', { expr = true })
vim.keymap.set({ 'x', 'n' }, '<M-<>', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w>>" : "<C-w><")', { expr = true })
vim.keymap.set({ 'x', 'n' }, '<M-.>', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w><" : "<C-w>>")', { expr = true })
vim.keymap.set({ 'x', 'n' }, '<M-,>', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w>>" : "<C-w><")', { expr = true })

vim.keymap.set({ 'x', 'n' }, '<C-w>>', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w><" : "<C-w>>")', { expr = true })
vim.keymap.set({ 'x', 'n' }, '<C-w><', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w>>" : "<C-w><")', { expr = true })
vim.keymap.set({ 'x', 'n' }, '<C-w>,', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w><" : "<C-w>>")', { expr = true })
vim.keymap.set({ 'x', 'n' }, '<C-w>.', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w>>" : "<C-w><")', { expr = true })
vim.keymap.set({ 'x', 'n' }, '<C-w>+', 'v:count ? "<C-w>+" : "2<C-w>+"', { expr = true })
vim.keymap.set({ 'x', 'n' }, '<C-w>-', 'v:count ? "<C-w>-" : "2<C-w>-"', { expr = true })
-- stylua: ignore end

-- Terminal mode keymaps
-- stylua: ignore start
vim.keymap.set('t', '<C-6>', [[v:lua.require'utils.term'.running_tui() ? "<C-6>" : "<Cmd>b#<CR>"]],        { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<C-^>', [[v:lua.require'utils.term'.running_tui() ? "<C-^>" : "<Cmd>b#<CR>"]],        { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<Esc>', [[v:lua.require'utils.term'.running_tui() ? "<Esc>" : "<Cmd>stopi<CR>"]],     { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-v>', [[v:lua.require'utils.term'.running_tui() ? "<M-v>" : "<Cmd>wincmd v<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-s>', [[v:lua.require'utils.term'.running_tui() ? "<M-s>" : "<Cmd>wincmd s<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-W>', [[v:lua.require'utils.term'.running_tui() ? "<M-W>" : "<Cmd>wincmd W<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-H>', [[v:lua.require'utils.term'.running_tui() ? "<M-H>" : "<Cmd>wincmd H<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-J>', [[v:lua.require'utils.term'.running_tui() ? "<M-J>" : "<Cmd>wincmd J<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-K>', [[v:lua.require'utils.term'.running_tui() ? "<M-K>" : "<Cmd>wincmd K<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-L>', [[v:lua.require'utils.term'.running_tui() ? "<M-L>" : "<Cmd>wincmd L<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-r>', [[v:lua.require'utils.term'.running_tui() ? "<M-r>" : "<Cmd>wincmd r<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-R>', [[v:lua.require'utils.term'.running_tui() ? "<M-R>" : "<Cmd>wincmd R<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-x>', [[v:lua.require'utils.term'.running_tui() ? "<M-x>" : "<Cmd>wincmd x<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-p>', [[v:lua.require'utils.term'.running_tui() ? "<M-p>" : "<Cmd>wincmd p<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-c>', [[v:lua.require'utils.term'.running_tui() ? "<M-c>" : "<Cmd>wincmd c<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-q>', [[v:lua.require'utils.term'.running_tui() ? "<M-q>" : "<Cmd>wincmd q<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-o>', [[v:lua.require'utils.term'.running_tui() ? "<M-o>" : "<Cmd>wincmd o<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-w>', [[v:lua.require'utils.term'.running_tui() ? "<M-w>" : "<Cmd>wincmd w<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-h>', [[v:lua.require'utils.term'.running_tui() ? "<M-h>" : "<Cmd>wincmd h<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-j>', [[v:lua.require'utils.term'.running_tui() ? "<M-j>" : "<Cmd>wincmd j<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-k>', [[v:lua.require'utils.term'.running_tui() ? "<M-k>" : "<Cmd>wincmd k<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-l>', [[v:lua.require'utils.term'.running_tui() ? "<M-l>" : "<Cmd>wincmd l<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-=>', [[v:lua.require'utils.term'.running_tui() ? "<M-=>" : "<Cmd>wincmd =<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-_>', [[v:lua.require'utils.term'.running_tui() ? "<M-_>" : "<Cmd>wincmd _<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-|>', [[v:lua.require'utils.term'.running_tui() ? "<M-|>" : "<Cmd>wincmd |<CR>"]],  { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-+>', [[v:lua.require'utils.term'.running_tui() ? "<M-+>" : "<Cmd>wincmd 2+<CR>"]], { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M-->', [[v:lua.require'utils.term'.running_tui() ? "<M-->" : "<Cmd>wincmd 2-<CR>"]], { expr = true, replace_keycodes = false })
vim.keymap.set('t', '<M->>', [[v:lua.require'utils.term'.running_tui() ? "<M->>" : "<Cmd>wincmd 4" . (winnr() == winnr("l") ? "<" : ">") . "<CR>"]], { expr = true })
vim.keymap.set('t', '<M-<>', [[v:lua.require'utils.term'.running_tui() ? "<M-<>" : "<Cmd>wincmd 4" . (winnr() == winnr("l") ? ">" : "<") . "<CR>"]], { expr = true })
vim.keymap.set('t', '<M-.>', [[v:lua.require'utils.term'.running_tui() ? "<M-.>" : "<Cmd>wincmd 4" . (winnr() == winnr("l") ? "<" : ">") . "<CR>"]], { expr = true })
vim.keymap.set('t', '<M-,>', [[v:lua.require'utils.term'.running_tui() ? "<M-,>" : "<Cmd>wincmd 4" . (winnr() == winnr("l") ? ">" : "<") . "<CR>"]], { expr = true })
-- stylua: ignore end

-- Use <C-\><C-r> to insert contents of a register in terminal mode
vim.keymap.set(
  't',
  [[<C-\><C-r>]],
  [['<C-\><C-n>"' . nr2char(getchar()) . 'pi']],
  { expr = true }
)

-- Past with correct indentation in insert mode
vim.keymap.set('i', '<C-r>', '<C-r><C-p>')

-- More consistent behavior when &wrap is set
-- stylua: ignore start
vim.keymap.set({ 'n', 'x' }, 'j', 'v:count ? "j" : "gj"', { expr = true })
vim.keymap.set({ 'n', 'x' }, 'k', 'v:count ? "k" : "gk"', { expr = true })
vim.keymap.set({ 'n', 'x' }, '<Down>', 'v:count ? "<Down>" : "g<Down>"', { expr = true, replace_keycodes = false })
vim.keymap.set({ 'n', 'x' }, '<Up>',   'v:count ? "<Up>"   : "g<Up>"',   { expr = true, replace_keycodes = false })
vim.keymap.set({ 'i' }, '<Down>', '<Cmd>norm! g<Down><CR>')
vim.keymap.set({ 'i' }, '<Up>',   '<Cmd>norm! g<Up><CR>')
-- stylua: ignore end

-- Buffer navigation
vim.keymap.set('n', ']b', '<Cmd>exec v:count1 . "bn"<CR>')
vim.keymap.set('n', '[b', '<Cmd>exec v:count1 . "bp"<CR>')

-- Tabpages
---@param tab_action function
---@param default_count number?
---@return function
local function tabswitch(tab_action, default_count)
  return function()
    local count = default_count or vim.v.count
    local num_tabs = vim.fn.tabpagenr('$')
    if num_tabs >= count then
      tab_action(count ~= 0 and count or nil)
      return
    end
    vim.cmd.tablast()
    for _ = 1, count - num_tabs do
      vim.cmd.tabnew()
    end
  end
end
vim.keymap.set({ 'n', 'x' }, 'gt', tabswitch(vim.cmd.tabnext))
vim.keymap.set({ 'n', 'x' }, 'gT', tabswitch(vim.cmd.tabprev))
vim.keymap.set({ 'n', 'x' }, 'gy', tabswitch(vim.cmd.tabprev)) -- gT is too hard to press

vim.keymap.set({ 'n', 'x' }, '<Leader>0', '<Cmd>0tabnew<CR>')
vim.keymap.set({ 'n', 'x' }, '<Leader>1', tabswitch(vim.cmd.tabnext, 1))
vim.keymap.set({ 'n', 'x' }, '<Leader>2', tabswitch(vim.cmd.tabnext, 2))
vim.keymap.set({ 'n', 'x' }, '<Leader>3', tabswitch(vim.cmd.tabnext, 3))
vim.keymap.set({ 'n', 'x' }, '<Leader>4', tabswitch(vim.cmd.tabnext, 4))
vim.keymap.set({ 'n', 'x' }, '<Leader>5', tabswitch(vim.cmd.tabnext, 5))
vim.keymap.set({ 'n', 'x' }, '<Leader>6', tabswitch(vim.cmd.tabnext, 6))
vim.keymap.set({ 'n', 'x' }, '<Leader>7', tabswitch(vim.cmd.tabnext, 7))
vim.keymap.set({ 'n', 'x' }, '<Leader>8', tabswitch(vim.cmd.tabnext, 8))
vim.keymap.set({ 'n', 'x' }, '<Leader>9', tabswitch(vim.cmd.tabnext, 9))

-- Correct misspelled word / mark as correct
vim.keymap.set('i', '<C-g>+', '<Esc>[szg`]a')
vim.keymap.set('i', '<C-g>=', '<C-g>u<Esc>[s1z=`]a<C-G>u')

-- Only clear highlights and message area and don't redraw if search
-- highlighting is on to avoid flickering
-- Use `:sil! dif` to suppress error
-- 'E11: Invalid in command-line window; <CR> executes, CTRL-C quits'
-- in command window
vim.keymap.set(
  { 'n', 'x' },
  '<C-l>',
  [['<Cmd>ec|noh|sil! dif<CR>' . (v:hlsearch ? '' : '<C-l>')]],
  { expr = true, replace_keycodes = false }
)

-- Don't include extra spaces around quotes
vim.keymap.set({ 'o', 'x' }, 'a"', '2i"', { noremap = false })
vim.keymap.set({ 'o', 'x' }, "a'", "2i'", { noremap = false })
vim.keymap.set({ 'o', 'x' }, 'a`', '2i`', { noremap = false })

-- Close all floating windows
vim.keymap.set({ 'n', 'x' }, 'q', function()
  require('utils.misc').q()
end)

-- Edit current file's directory
vim.keymap.set({ 'n', 'x' }, '-', '<Cmd>e%:p:h<CR>')

-- Enter insert mode, add a space after the cursor
vim.keymap.set({ 'n', 'x' }, '<M-i>', 'i<Space><Left>')
vim.keymap.set({ 'n', 'x' }, '<M-I>', 'I<Space><Left>')
vim.keymap.set({ 'n', 'x' }, '<M-a>', 'a<Space><Left>')
vim.keymap.set({ 'n', 'x' }, '<M-A>', 'A<Space><Left>')

-- Text object: current buffer
-- stylua: ignore start
vim.keymap.set('x', 'af', ':<C-u>silent! keepjumps normal! ggVG<CR>', { silent = true, noremap = false })
vim.keymap.set('x', 'if', ':<C-u>silent! keepjumps normal! ggVG<CR>', { silent = true, noremap = false })
vim.keymap.set('o', 'af', '<Cmd>silent! normal m`Vaf<CR><Cmd>silent! normal! ``<CR>', { silent = true, noremap = false })
vim.keymap.set('o', 'if', '<Cmd>silent! normal m`Vif<CR><Cmd>silent! normal! ``<CR>', { silent = true, noremap = false })
-- stylua: ignore end

-- stylua: ignore start
vim.keymap.set('x', 'iz', [[':<C-u>silent! keepjumps normal! ' . v:lua.require'utils.misc'.textobj_fold('i') . '<CR>']], { silent = true, expr = true, noremap = false })
vim.keymap.set('x', 'az', [[':<C-u>silent! keepjumps normal! ' . v:lua.require'utils.misc'.textobj_fold('a') . '<CR>']], { silent = true, expr = true, noremap = false })
vim.keymap.set('o', 'iz', '<Cmd>silent! normal Viz<CR>', { silent = true, noremap = false })
vim.keymap.set('o', 'az', '<Cmd>silent! normal Vaz<CR>', { silent = true, noremap = false })
-- stylua: ignore end

-- Use 'g{' and 'g}' to move to the first/last line of a paragraph
-- stylua: ignore start
vim.keymap.set({ 'o' }, 'g{', '<Cmd>silent! normal Vg{<CR>', { noremap = false })
vim.keymap.set({ 'o' }, 'g}', '<Cmd>silent! normal Vg}<CR>', { noremap = false })
vim.keymap.set({ 'n', 'x' }, 'g{', function() require('utils.misc').goto_paragraph_firstline() end, { noremap = false })
vim.keymap.set({ 'n', 'x' }, 'g}', function() require('utils.misc').goto_paragraph_lastline() end, { noremap = false })
-- stylua: ignore end

-- Fzf keymaps
vim.keymap.set('n', '<Leader>.', '<Cmd>FZF<CR>')
vim.keymap.set('n', '<Leader>ff', '<Cmd>FZF<CR>')

-- Abbreviations
vim.keymap.set('!a', 'ture', 'true')
vim.keymap.set('!a', 'Ture', 'True')
vim.keymap.set('!a', 'flase', 'false')
vim.keymap.set('!a', 'fasle', 'false')
vim.keymap.set('!a', 'Flase', 'False')
vim.keymap.set('!a', 'Fasle', 'False')
vim.keymap.set('!a', 'lcaol', 'local')
vim.keymap.set('!a', 'lcoal', 'local')
vim.keymap.set('!a', 'locla', 'local')
vim.keymap.set('!a', 'sahre', 'share')
vim.keymap.set('!a', 'saher', 'share')
vim.keymap.set('!a', 'balme', 'blame')

vim.api.nvim_create_autocmd('CmdlineEnter', {
  once = true,
  callback = function()
    local utils = require('utils')
    utils.keymap.command_map(':', 'lua ')
    utils.keymap.command_abbrev('man', 'Man')
    utils.keymap.command_abbrev('ht', 'hor te')
    utils.keymap.command_abbrev('vt', 'vert te')
    utils.keymap.command_abbrev('rm', '!rm')
    utils.keymap.command_abbrev('mv', '!mv')
    utils.keymap.command_abbrev('git', '!git')
    utils.keymap.command_abbrev('mkd', '!mkdir')
    utils.keymap.command_abbrev('mkdir', '!mkdir')
    utils.keymap.command_abbrev('touch', '!touch')
    return true
  end,
})
