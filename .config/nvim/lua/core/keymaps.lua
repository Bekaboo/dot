vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Multi-window operations
-- stylua: ignore start
vim.keymap.set({ 'x', 'n' }, '<M-w>', '<C-w>w', { desc = 'Cycle through windows' })
vim.keymap.set({ 'x', 'n' }, '<M-W>', '<C-w>W', { desc = 'Cycle through windows reversely' })
vim.keymap.set({ 'x', 'n' }, '<M-H>', '<C-w>H', { desc = 'Move window to far left' })
vim.keymap.set({ 'x', 'n' }, '<M-J>', '<C-w>J', { desc = 'Move winow to very bottom' })
vim.keymap.set({ 'x', 'n' }, '<M-K>', '<C-w>K', { desc = 'Move window to very top' })
vim.keymap.set({ 'x', 'n' }, '<M-L>', '<C-w>L', { desc = 'Move window to far right' })
vim.keymap.set({ 'x', 'n' }, '<M-p>', '<C-w>p', { desc = 'Go to the previous window' })
vim.keymap.set({ 'x', 'n' }, '<M-r>', '<C-w>r', { desc = 'Rotate windows downwords/rightwards' })
vim.keymap.set({ 'x', 'n' }, '<M-R>', '<C-w>r', { desc = 'Rotate windows upwards/leftwords' })
vim.keymap.set({ 'x', 'n' }, '<M-v>', '<C-w>v', { desc = 'Split window vertically' })
vim.keymap.set({ 'x', 'n' }, '<M-s>', '<C-w>s', { desc = 'Split window horizontally' })
vim.keymap.set({ 'x', 'n' }, '<M-x>', '<C-w>x', { desc = 'Exchange current window with next one' })
vim.keymap.set({ 'x', 'n' }, '<M-z>', '<C-w>z', { desc = 'Close preview window' })
vim.keymap.set({ 'x', 'n' }, '<M-c>', '<C-w>c', { desc = 'Close current window' })
vim.keymap.set({ 'x', 'n' }, '<M-q>', '<C-w>q', { desc = 'Quit current window' })
vim.keymap.set({ 'x', 'n' }, '<M-n>', '<C-w>n', { desc = 'Create new window' })
vim.keymap.set({ 'x', 'n' }, '<M-o>', '<C-w>o', { desc = 'Make current window the only one' })
vim.keymap.set({ 'x', 'n' }, '<M-t>', '<C-w>t', { desc = 'Go to the top-left window' })
vim.keymap.set({ 'x', 'n' }, '<M-T>', '<C-w>T', { desc = 'Move window to new tab' })
vim.keymap.set({ 'x', 'n' }, '<M-]>', '<C-w>]', { desc = 'Split and jump to tag under cursor' })
vim.keymap.set({ 'x', 'n' }, '<M-^>', '<C-w>^', { desc = 'Split and edit alternate file' })
vim.keymap.set({ 'x', 'n' }, '<M-b>', '<C-w>b', { desc = 'Go to the bottom-right window' })
vim.keymap.set({ 'x', 'n' }, '<M-d>', '<C-w>d', { desc = 'Split and jump to definition' })
vim.keymap.set({ 'x', 'n' }, '<M-f>', '<C-w>f', { desc = 'Split and edit file under cursor' })
vim.keymap.set({ 'x', 'n' }, '<M-}>', '<C-w>}', { desc = 'Show tag under cursor in preview window' })
vim.keymap.set({ 'x', 'n' }, '<M-g>]', '<C-w>g]', { desc = 'Split and select tag under cursor' })
vim.keymap.set({ 'x', 'n' }, '<M-g>}', '<C-w>g}', { desc = 'Show tag under cursor in preview window' })
vim.keymap.set({ 'x', 'n' }, '<M-g>f', '<C-w>gf', { desc = 'Edit file under cursor in new tab' })
vim.keymap.set({ 'x', 'n' }, '<M-g>F', '<C-w>gF', { desc = 'Edit file under cursor in new tab and jump to line' })
vim.keymap.set({ 'x', 'n' }, '<M-g>t', '<C-w>gt', { desc = 'Go to next tab' })
vim.keymap.set({ 'x', 'n' }, '<M-g>T', '<C-w>gT', { desc = 'Go to previous tab' })
vim.keymap.set({ 'x', 'n' }, '<M-h>', '<C-w><C-h>', { desc = 'Go to the left window' })
vim.keymap.set({ 'x', 'n' }, '<M-j>', '<C-w><C-j>', { desc = 'Go to the window below' })
vim.keymap.set({ 'x', 'n' }, '<M-k>', '<C-w><C-k>', { desc = 'Go to the window above' })
vim.keymap.set({ 'x', 'n' }, '<M-l>', '<C-w><C-l>', { desc = 'Go to the right window' })
vim.keymap.set({ 'x', 'n' }, '<M-Left>', '<C-w><Left>', { desc = 'Go to the left window' })
vim.keymap.set({ 'x', 'n' }, '<M-Down>', '<C-w><Down>', { desc = 'Go to the window below' })
vim.keymap.set({ 'x', 'n' }, '<M-Up>', '<C-w><Up>', { desc = 'Go to the window above' })
vim.keymap.set({ 'x', 'n' }, '<M-Right>', '<C-w><Right>', { desc = 'Go to the right window' })
vim.keymap.set({ 'x', 'n' }, '<M-g><M-]>', '<C-w>g<C-]>', { desc = 'Split and jump to tag under cursor' })
vim.keymap.set({ 'x', 'n' }, '<M-g><Tab>', '<C-w>g<Tab>', { desc = 'Go to last accessed tab' })

vim.keymap.set({ 'x', 'n' }, '<M-=>', '<C-w>=', { desc = 'Make all windows equal size' })
vim.keymap.set({ 'x', 'n' }, '<M-_>', '<C-w>_', { desc = 'Set current window height to maximum' })
vim.keymap.set({ 'x', 'n' }, '<M-|>', '<C-w>|', { desc = 'Set current window width to maximum' })
vim.keymap.set({ 'x', 'n' }, '<M-+>', 'v:count ? "<C-w>+" : "2<C-w>+"', { expr = true, desc = 'Increase window height' })
vim.keymap.set({ 'x', 'n' }, '<M-->', 'v:count ? "<C-w>-" : "2<C-w>-"', { expr = true, desc = 'Decrease window height' })
vim.keymap.set({ 'x', 'n' }, '<M->>', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w><" : "<C-w>>")', { expr = true, desc = 'Resize window right' })
vim.keymap.set({ 'x', 'n' }, '<M-.>', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w><" : "<C-w>>")', { expr = true, desc = 'Resize window right' })
vim.keymap.set({ 'x', 'n' }, '<M-<>', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w>>" : "<C-w><")', { expr = true, desc = 'Resize window left' })
vim.keymap.set({ 'x', 'n' }, '<M-,>', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w>>" : "<C-w><")', { expr = true, desc = 'Resize window left' })

vim.keymap.set({ 'x', 'n' }, '<C-w>>', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w><" : "<C-w>>")', { expr = true, desc = 'Resize window right' })
vim.keymap.set({ 'x', 'n' }, '<C-w>.', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w>>" : "<C-w><")', { expr = true, desc = 'Resize window right' })
vim.keymap.set({ 'x', 'n' }, '<C-w><', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w>>" : "<C-w><")', { expr = true, desc = 'Resize window left' })
vim.keymap.set({ 'x', 'n' }, '<C-w>,', '(v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w><" : "<C-w>>")', { expr = true, desc = 'Resize window left' })
vim.keymap.set({ 'x', 'n' }, '<C-w>+', 'v:count ? "<C-w>+" : "2<C-w>+"', { expr = true, desc = 'Increase window height' })
vim.keymap.set({ 'x', 'n' }, '<C-w>-', 'v:count ? "<C-w>-" : "2<C-w>-"', { expr = true, desc = 'Decrease window height' })
-- stylua: ignore end

-- Wisely exit terminal mode with <Esc>
vim.keymap.set(
  't',
  '<Esc>',
  [[v:lua.require'utils.term'.running_tui() ? "<Esc>" : "<Cmd>stopi<CR>"]],
  { expr = true, replace_keycodes = false, desc = 'Exit terminal mode' }
)

-- Use <C-\><C-r> to insert contents of a register in terminal mode
vim.keymap.set(
  't',
  [[<C-\><C-r>]],
  [['<C-\><C-n>"' . nr2char(getchar()) . 'pi']],
  { expr = true, desc = 'Insert contents in a register' }
)

-- Delete selection in select mode
vim.keymap.set('s', '<BS>', '<C-o>s', { desc = 'Delete selection' })
vim.keymap.set('s', '<C-h>', '<C-o>s', { desc = 'Delete selection' })

-- More consistent behavior when &wrap is set
-- stylua: ignore start
vim.keymap.set({ 'n', 'x' }, 'j', 'v:count ? "j" : "gj"', { expr = true, desc = 'Move down' })
vim.keymap.set({ 'n', 'x' }, 'k', 'v:count ? "k" : "gk"', { expr = true, desc = 'Move up' })
vim.keymap.set({ 'n', 'x' }, '<Down>', 'v:count ? "<Down>" : "g<Down>"', { expr = true, replace_keycodes = false, desc = 'Move down' })
vim.keymap.set({ 'n', 'x' }, '<Up>',   'v:count ? "<Up>"   : "g<Up>"',   { expr = true, replace_keycodes = false, desc = 'Move up' })
vim.keymap.set({ 'i' }, '<Down>', '<Cmd>norm! g<Down><CR>', { desc = 'Move down' })
vim.keymap.set({ 'i' }, '<Up>',   '<Cmd>norm! g<Up><CR>',   { desc = 'Move up' })

-- Buffer navigation
vim.keymap.set('n', ']b', '<Cmd>exec v:count1 . "bn"<CR>', { desc = 'Go to next buffer' })
vim.keymap.set('n', '[b', '<Cmd>exec v:count1 . "bp"<CR>', { desc = 'Go to previous buffer' })

-- Quickfix/location list navigation
vim.keymap.set('n', '[q', '<Cmd>exec v:count1 . "cp"<CR>', { desc = 'Go to previous quickfix item' })
vim.keymap.set('n', '[l', '<Cmd>exec v:count1 . "lp"<CR>', { desc = 'Go to previous location list item' })
vim.keymap.set('n', ']q', '<Cmd>exec v:count1 . "cne"<CR>', { desc = 'Go to next quickfix item' })
vim.keymap.set('n', ']l', '<Cmd>exec v:count1 . "lne"<CR>', { desc = 'Go to next location list item' })
vim.keymap.set('n', '[Q', '<Cmd>exec v:count1 . "cfir"<CR>', { desc = 'Go to first quickfix item' })
vim.keymap.set('n', '[L', '<Cmd>exec v:count1 . "lfir"<CR>', { desc = 'Go to first location list item' })
vim.keymap.set('n', ']Q', '<Cmd>exec (v:count ? v:count : "") . "cla"<CR>', { desc = 'Go to last quickfix item' })
vim.keymap.set('n', ']L', '<Cmd>exec (v:count ? v:count : "") . "lla"<CR>', { desc = 'Go to last location list item' })
-- stylua: ignore end

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
-- stylua: ignore start
vim.keymap.set({ 'n', 'x' }, 'gt', tabswitch(vim.cmd.tabnext), { desc = 'Go to next tab' })
vim.keymap.set({ 'n', 'x' }, 'gT', tabswitch(vim.cmd.tabprev), { desc = 'Go to previous tab' })

-- Correct misspelled word / mark as correct
vim.keymap.set('i', '<C-g>+', '<Esc>[szg`]a', { desc = 'Correct misspelled word before cursor' })
vim.keymap.set('i', '<C-g>=', '<C-g>u<Esc>[s1z=`]a<C-G>u', { desc = 'Add misspelled word before cursor' })
-- stylua: ignore end

-- Only clear highlights and message area and don't redraw if search
-- highlighting is on to avoid flickering
-- Use `:sil! dif` to suppress error
-- 'E11: Invalid in command-line window; <CR> executes, CTRL-C quits'
-- in command window
vim.keymap.set(
  { 'n', 'x' },
  '<C-l>',
  [['<Cmd>ec|noh|sil! dif<CR>' . (v:hlsearch ? '' : '<C-l>')]],
  { expr = true, replace_keycodes = false, desc = 'Clear and redraw screen' }
)

-- Don't include extra spaces around quotes
-- stylua: ignore start
vim.keymap.set({ 'o', 'x' }, 'a"', '2i"', { noremap = false, desc = 'Selet around double quotes' })
vim.keymap.set({ 'o', 'x' }, "a'", "2i'", { noremap = false, desc = 'Selet around single quotes' })
vim.keymap.set({ 'o', 'x' }, 'a`', '2i`', { noremap = false, desc = 'Selet around backticks' })

-- Close all floating windows
vim.keymap.set({ 'n', 'x' }, 'q', function() require('utils.misc').close_floats('q') end, { desc = 'Close all floating windows or start recording macro' })
vim.keymap.set('n', '<Esc>', function() require('utils.misc').close_floats('<Esc>') end, { desc = 'Close all floating windows' })

-- Edit current file's directory
vim.keymap.set({ 'n', 'x' }, '-', '<Cmd>e%:p:h<CR>', { desc = 'Edit current file\'s directory' })

-- Enter insert mode, add a space after the cursor
vim.keymap.set({ 'n', 'x' }, '<M-i>', 'i<Space><Left>', { desc = 'Insert with a space after the cursor' })
vim.keymap.set({ 'n', 'x' }, '<M-I>', 'I<Space><Left>', { desc = 'Insert at start of line or selection with a space after the cursor' })
vim.keymap.set({ 'n', 'x' }, '<M-a>', 'a<Space><Left>', { desc = 'Append with a space after the cursor' })
vim.keymap.set({ 'n', 'x' }, '<M-A>', 'A<Space><Left>', { desc = 'Append at end of line or selection with a space after the cursor' })

-- Text object: current buffer
vim.keymap.set('x', 'af', ':<C-u>silent! keepjumps normal! ggVG<CR>', { silent = true, noremap = false, desc = 'Select current buffer' })
vim.keymap.set('x', 'if', ':<C-u>silent! keepjumps normal! ggVG<CR>', { silent = true, noremap = false, desc = 'Select current buffer' })
vim.keymap.set('o', 'af', '<Cmd>silent! normal m`Vaf<CR><Cmd>silent! normal! ``<CR>', { silent = true, noremap = false, desc = 'Select current buffer' })
vim.keymap.set('o', 'if', '<Cmd>silent! normal m`Vif<CR><Cmd>silent! normal! ``<CR>', { silent = true, noremap = false, desc = 'Select current buffer' })

vim.keymap.set('x', 'iz', [[':<C-u>silent! keepjumps normal! ' . v:lua.require'utils.misc'.textobj_fold('i') . '<CR>']], { silent = true, expr = true, noremap = false, desc = 'Select inside current fold' })
vim.keymap.set('x', 'az', [[':<C-u>silent! keepjumps normal! ' . v:lua.require'utils.misc'.textobj_fold('a') . '<CR>']], { silent = true, expr = true, noremap = false, desc = 'Select around current fold' })
vim.keymap.set('o', 'iz', '<Cmd>silent! normal Viz<CR>', { silent = true, noremap = false, desc = 'Select inside current fold' })
vim.keymap.set('o', 'az', '<Cmd>silent! normal Vaz<CR>', { silent = true, noremap = false, desc = 'Select around current fold' })

-- Use 'g{' and 'g}' to go to the first/last line of a paragraph
vim.keymap.set({ 'o' }, 'g{', '<Cmd>silent! normal Vg{<CR>', { noremap = false, desc = 'Go to the first line of paragraph' })
vim.keymap.set({ 'o' }, 'g}', '<Cmd>silent! normal Vg}<CR>', { noremap = false, desc = 'Go to the last line of paragraph' })
vim.keymap.set({ 'n', 'x' }, 'g{', function() require('utils.misc').goto_paragraph_firstline() end, { noremap = false, desc = 'Go to the first line of paragraph' })
vim.keymap.set({ 'n', 'x' }, 'g}', function() require('utils.misc').goto_paragraph_lastline() end, { noremap = false, desc = 'Go to the last line of paragraph' })
-- stylua: ignore end

-- Fzf keymaps
vim.keymap.set('n', '<Leader>.', '<Cmd>FZF<CR>', { desc = 'Find files' })
vim.keymap.set('n', '<Leader>ff', '<Cmd>FZF<CR>', { desc = 'Find files' })

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
    utils.keymap.command_abbrev('tt', 'tab te')
    utils.keymap.command_abbrev('bt', 'bot te')
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
