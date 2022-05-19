-------------------------------------------------------------------------------
-- KEYMAPPINGS ----------------------------------------------------------------
-------------------------------------------------------------------------------
-- NOTICE: Not all keymappings are kept in this file
-- Only general keymappings are kept here
-- Plugin-specific keymappings are kept in corresponding
-- config files for that plugin

local map = vim.keymap.set
local g = vim.g

-- Map leader key to space
map('n', '<Space>', '', {})
g.mapleader = ' '

-- Map esc key
map('i', 'jj', '<esc>', {noremap = true})

-- Exit from term mode
map('t', '\\<C-\\>', '<C-\\><C-n>', {noremap = true})

-- Toggle hlsearch
map('n', '\\', '<cmd>set hlsearch!<CR>', {noremap = true})
map('n', '/', '/<cmd>set hlsearch<CR>', {noremap = true})
map('n', '?', '?<cmd>set hlsearch<CR>', {noremap = true})
map('n', '*', '*<cmd>set hlsearch<CR>', {noremap = true})
map('n', '#', '#<cmd>set hlsearch<CR>', {noremap = true})
map('n', 'g*', 'g*<cmd>set hlsearch<CR>', {noremap = true})
map('n', 'g#', 'g#<cmd>set hlsearch<CR>', {noremap = true})
map('n', 'n', 'n<cmd>set hlsearch<CR>', {noremap = true})
map('n', 'N', 'N<cmd>set hlsearch<CR>', {noremap = true})

-- Multi-window operations
map('n', '<M-w>', '<C-w><C-w>', {noremap = true})
map('n', '<M-h>', '<C-w><C-h>', {noremap = true})
map('n', '<M-j>', '<C-w><C-j>', {noremap = true})
map('n', '<M-k>', '<C-w><C-k>', {noremap = true})
map('n', '<M-l>', '<C-w><C-l>', {noremap = true})
map('n', '<M-W>', '<C-w>W', {noremap = true})
map('n', '<M-H>', '<C-w>H', {noremap = true})
map('n', '<M-J>', '<C-w>J', {noremap = true})
map('n', '<M-K>', '<C-w>K', {noremap = true})
map('n', '<M-L>', '<C-w>L', {noremap = true})
map('n', '<M-=>', '<C-w>=', {noremap = true})
map('n', '<M-->', '<C-w>-', {noremap = true})
map('n', '<M-+>', '<C-w>+', {noremap = true})
map('n', '<M-_>', '<C-w>_', {noremap = true})
map('n', '<M-|>', '<C-w>|', {noremap = true})
map('n', '<M-,>', '<C-w><', {noremap = true})
map('n', '<M-.>', '<C-w>>', {noremap = true})
map('n', '<M-p>', '<C-w>p', {noremap = true})
map('n', '<M-r>', '<C-w>r', {noremap = true})
map('n', '<M-v>', '<C-w>v', {noremap = true})
map('n', '<M-s>', '<C-w>s', {noremap = true})
map('n', '<M-x>', '<C-w>x', {noremap = true})
map('n', '<M-z>', '<C-w>z', {noremap = true})
map('n', '<M-c>', '<C-w>c', {noremap = true})   -- Close current window
map('n', '<M-o>', '<C-w>o', {noremap = true})   -- Close all other windows
map('n', '<M-t>', '<C-w>t', {noremap = true})
map('n', '<M-T>', '<C-w>T', {noremap = true})
map('n', '<M-]>', '<C-w>]', {noremap = true})
map('n', '<M-^>', '<C-w>^', {noremap = true})
map('n', '<M-b>', '<C-w>b', {noremap = true})
map('n', '<M-d>', '<C-w>d', {noremap = true})
map('n', '<M-f>', '<C-w>f', {noremap = true})
map('n', '<M-g><M-]>', '<C-w>g<C-]>', {noremap = true})
map('n', '<M-g>]', '<C-w>g]', {noremap = true})
map('n', '<M-g>}', '<C-w>g}', {noremap = true})
map('n', '<M-g>f', '<C-w>gf', {noremap = true})
map('n', '<M-g>F', '<C-w>gF', {noremap = true})
map('n', '<M-g>t', '<C-w>gt', {noremap = true})
map('n', '<M-g>T', '<C-w>gT', {noremap = true})
map('n', '<M-g><Tab>', '<C-w>g<Tab>', {noremap = true})
map('n', '<M-}>', '<C_w>}', {noremap = true})

-- From https://github.com/wookayin/dotfiles/commit/96d935515486f44ec361db3df8ab9ebb41ea7e40
function _G.close_all_floatings()
  local closed_windows = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local config = vim.api.nvim_win_get_config(win)
    if config.relative ~= '' then         -- is_floating_window?
      vim.api.nvim_win_close(win, false)  -- do not force
      table.insert(closed_windows, win)
    end
  end
  print(string.format ('Closed %d windows: %s', #closed_windows,
                       vim.inspect(closed_windows)))
end

-- Close all floating windows
map('n','<M-;>', "<cmd>lua close_all_floatings()<CR>", {noremap = true})


-- Multi-buffer operations
map('n', '<Tab>', '<cmd>bn<CR>', {noremap = true})
map('n', '<S-Tab>', '<cmd>bp<CR>', {noremap = true})
map('n', '<M-d>', '<cmd>bd<CR>', {noremap = true})  -- Delete current buffer
map('n', '<C-n>', '<C-i>', {noremap = true})        -- <Tab> / <C-i> is used to switch buffers
                                                    -- so use <C-n> to jump to newer cursor
                                                    -- position instead

-- Moving in insert and command-line mode
map({'i', 'c'}, '<M-h>', '<left>', {noremap = true})
map({'i', 'c'}, '<M-j>', '<down>', {noremap = true})
map({'i', 'c'}, '<M-k>', '<up>', {noremap = true})
map({'i', 'c'}, '<M-l>', '<right>', {noremap = true})

-- -- Patch for pairing
-- execute
-- [[
-- inoremap (                      ()<left>
-- inoremap [                      []<left>
-- inoremap {                      {}<left>
-- inoremap "                      ""<left>
-- inoremap '                      ''<left>
-- inoremap `                      ``<left>
-- " For c struct definition
-- inoremap <silent>;              <C-r>=CStructDef()<CR>

-- " Auto indentation in paired brackets/parenthesis/tags, etc.
-- inoremap <silent><CR>           <C-r>=PairedIndent()<CR>

-- " Auto delete paired brackets/parenthesis/tags, etc.
-- inoremap <silent><BackSpace>    <C-r>=PairedDelete()<CR>

-- inoremap <silent><Space>        <C-r>=PairedSpace()<CR>

-- "" Functions:
-- func PairedIndent ()
--     let c = getline('.')[col('.') - 1]
--     let p = getline('.')[col('.') - 2]
--     if ')' == c && '(' == p || ']' == c && '[' == p || '}' == c && '{' == p ||
--         \"'" == c && '"' == p || '`' == c && '`' == p
--         return "\<cr>\<esc>O"
--     endif
--     if ')' == c || ']' == c || '}' == c
--         let command = printf("\<esc>di%si\<cr>\<esc>Pli\<cr>\<esc>k>>A", c)
--         return command
--     endif
--     return "\<cr>"
-- endfunc

-- func PairedDelete ()
--     let c = getline('.')[col('.') - 1]
--     let p = getline('.')[col('.') - 2]
--     let pp = getline('.')[col('.') - 3]
--     let s = getline('.')[col('.')]
--     if ')' == c && '(' == p || ']' == c && '[' == p || '}' == c && '{' == p || 
--         \'>' == c && '<' == p || '"' == c && '"' == p || "'" == c && "'" == p ||
--         \'`' == c && '`' == p
--         if ';' != s
--             return "\<backspace>\<delete>"
--         endif
--         if ';' == s && 'c' == &filetype
--             return "\<backspace>\<delete>\<delete>"
--         elseif ';' == s && 'c' != &filetype
--             return "\<backspace>\<delete>"
--         endif
--     endif
--     if ' ' == p && ' ' == c &&
--         \(')' == s && '(' == pp || ']' == s && '[' == pp || '}' == s && '{' == pp || 
--         \'>' == s && '<' == pp || '"' == s && '"' == pp || "'" == s && "'" == pp ||
--         \'`' == s && '`' == pp)
--         return "\<backspace>\<delete>"
--     endif
--     return "\<backspace>"
-- endfunc

-- func PairedSpace ()
--     let c = getline('.')[col('.') - 1]
--     let p = getline('.')[col('.') - 2]
--     if ')' == c && '(' == p || ']' == c && '[' == p || '}' == c && '{' == p
--         return "\<space>\<space>\<left>"
--     endif
--     return "\<space>"
-- endfunc

-- func CStructDef ()
--     let c = getline('.')[col('.') - 1]
--     let p = getline('.')[col('.') - 2]
--     if '}' == c && '{' == p && 'c' == &filetype
--         return "\<right>;\<left>\<left>"
--     endif
--     return ";"
-- endfunc
-- ]]
