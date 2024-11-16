local M = {}
local api = vim.api
local fn = vim.fn
local map = vim.keymap.set
local col = vim.fn.col
local line = vim.fn.line

local regex_keyword_at_beginning = vim.regex([=[^\s*[[:keyword:]]*]=])
local regex_nonkeyword_at_beginning =
  vim.regex([=[^\s*[^[:keyword:][:space:]]*]=])
local regex_keyword_at_end = vim.regex([=[[[:keyword:]]*\s*$]=])
local regex_nonkeyword_at_end = vim.regex([=[[^[:keyword:][:space:]]*\s*$]=])

---Check if string is empty
---@param str string
---@return boolean
local function str_isempty(str)
  return str:gsub('%s+', '') == ''
end

---Match non-empty string
---@param str string
---@vararg vim.regex compiled vim regex
---@return string
local function match_nonempty(str, ...)
  local patterns = { ... }
  local capture = ''
  for _, pattern in ipairs(patterns) do
    local match_start, match_end = pattern:match_str(str)
    capture = match_start and str:sub(match_start + 1, match_end) or capture
    if not str_isempty(capture) then
      return capture
    end
  end
  return capture
end

---Get current line
---@return string
local function get_current_line()
  return fn.mode() == 'c' and fn.getcmdline() or api.nvim_get_current_line()
end

---Get current column number
---@return integer
local function get_current_col()
  return fn.mode() == 'c' and fn.getcmdpos() or col('.')
end

---Get word after cursor
---@param str string? content of the line, default to current line
---@param colnr integer? column number, default to current column
---@return string
local function get_word_after(str, colnr)
  str = str or get_current_line()
  colnr = colnr or get_current_col()
  return match_nonempty(
    str:sub(colnr),
    regex_keyword_at_beginning,
    regex_nonkeyword_at_beginning
  )
end

---Get word before cursor
---@param str string? content of the line, default to current line
---@param colnr integer? column number, default to current column - 1
---@return string
local function get_word_before(str, colnr)
  str = str or get_current_line()
  colnr = colnr or get_current_col() - 1
  return match_nonempty(
    str:sub(1, colnr),
    regex_keyword_at_end,
    regex_nonkeyword_at_end
  )
end

---Check if current line is the last line
---@return boolean
local function last_line()
  return fn.mode() == 'c' or line('.') == line('$')
end

---Check if current line is the first line
---@return boolean
local function first_line()
  return fn.mode() == 'c' or line('.') == 1
end

---Check if cursor is at the end of the line
---@return boolean
local function end_of_line()
  return get_current_col() == #get_current_line() + 1
end

---Check if cursor is at the start of the line
---@return boolean
local function start_of_line()
  return get_current_col() == 1
end

---Callback function for small delete, e.g. `<C-w>`, `<M-BS>`, `<M-d>`, `<C-k>`,
---`<C-u>`, etc keymaps; sets the small delete register '-' properly, should be
---used with `{ expr = true }`
---@param text_deleted string
---@param forward boolean
---@return string
local function small_del(text_deleted, forward)
  -- Lock to prevent next deletion before current deletion action completes.
  -- If we don't set this lock we might get and save wrong (old) cursor position
  -- in CmdlineChanged/TextChangedI callbacks, which will cause the '-' register
  -- to be reset undesirably.
  if vim.g._rl_del_lock or text_deleted == '' then
    return ''
  end
  vim.g._rl_del_lock = true

  local in_cmdline = vim.fn.mode() == 'c'
  -- We want to concatenate the deleted text in the '-' register if we are
  -- deleting 'continuously'. In insert mode, 'continuously' means that, after
  -- previous deletion, there is no changes in the buffer and the cursor stays
  -- in the same position; in cmdline mode, this means we are editing the same
  -- command line (both type and contents) and the cursor position is the same
  -- after previous deletion.
  -- In other cases, we reset the '-' register with the new deleted text.
  local reset = not (
    in_cmdline
      and fn.getcmdline() == vim.g._rl_cmd
      and fn.getcmdtype() == vim.g._rl_cmd_type
      and vim.deep_equal(vim.g._rl_cmd_pos, fn.getcmdpos())
    or not in_cmdline
      and vim.b.changedtick == vim.b._rl_changedtick
      and vim.deep_equal(vim.b._rl_del_pos, fn.getcurpos())
  )
  local reg_contents = reset and '' or fn.getreg('-')
  local reg_new_contents = forward and reg_contents .. text_deleted
    or text_deleted .. reg_contents
  fn.setreg('-', reg_new_contents)

  -- Record the cursor position after deleting the text
  if in_cmdline then
    vim.api.nvim_create_autocmd('CmdlineChanged', {
      once = true,
      callback = function()
        vim.schedule(function()
          vim.g._rl_cmd = fn.getcmdline()
          vim.g._rl_cmd_pos = fn.getcmdpos()
          vim.g._rl_cmd_type = fn.getcmdtype()
          vim.g._rl_del_lock = nil
        end)
        return true
      end,
    })
  else
    vim.api.nvim_create_autocmd('TextChangedI', {
      once = true,
      callback = function()
        vim.b._rl_del_pos = fn.getcurpos()
        vim.b._rl_changedtick = vim.b.changedtick
        vim.g._rl_del_lock = nil
        return true
      end,
    })
  end

  -- Temporarily include '[' (left key) in 'whichwrap' to allow moving cursor
  -- to the previous line on `<Left>`, this allows us to move to beginning
  -- of the texts to be deleted then delete then with `<Del>` keys
  if not forward and not in_cmdline then
    vim.g._rl_ww = vim.go.ww
    vim.opt.ww:append('[')
    vim.api.nvim_create_autocmd('TextChangedI', {
      once = true,
      callback = function()
        if vim.g._rl_ww then
          vim.go.ww = vim.g._rl_ww
          vim.g._rl_ww = nil
        end
        return true
      end,
    })
  end

  -- Use `<C-g>u` to start a new change for each word deletion
  -- Use `<Left>` and `<Del>` instead of `<BS>` to delete backward
  -- to avoid deleting multiple indent backspaces in one `<BS>`
  return (
    (in_cmdline and '' or '<C-g>u')
    .. (forward and '' or string.rep('<Left>', #text_deleted))
    .. string.rep('<Del>', #text_deleted)
  )
end

---Set up key mappings
function M.setup()
  if vim.g.loaded_readline then
    return
  end
  vim.g.loaded_readline = true

  -- Default 'cedit' is `<C-f>` which is taken by readline keymap
  if vim.go.cedit == vim.keycode('<C-f>') then
    vim.go.cedit = '<C-o>'
  end

  -- stylua: ignore start
  map('!', '<C-d>', '<Del>', { desc = 'Delete character under cursor' })
  map('c', '<C-b>', '<Left>', { desc = 'Move cursor backward' })
  map('c', '<C-f>', '<Right>', { desc = 'Move cursor forward' })

  map('!', '<C-BS>', '<C-w>', { remap = true, desc = 'Delete word before cursor' })
  map('!', '<M-BS>', '<C-w>', { remap = true, desc = 'Delete word before cursor' })
  map('!', '<M-Del>', '<C-w>', { remap = true, desc = 'Delete word before cursor' })
  -- stylua: ignore end
  map('!', '<C-w>', function()
    return small_del(
      start_of_line() and not first_line() and '\n' or get_word_before(),
      false
    )
  end, { expr = true, desc = 'Delete word before cursor' })

  map('!', '<M-d>', function()
    return small_del(
      end_of_line() and not last_line() and '\n' or get_word_after(),
      true
    )
  end, { expr = true, desc = 'Delete word after cursor' })

  map('!', '<C-k>', function()
    return small_del(
      end_of_line() and not last_line() and '\n'
        or get_current_line():sub(get_current_col()),
      true
    )
  end, { expr = true, desc = 'Delete text until the end of the line' })

  map('!', '<C-u>', function()
    local line_before = get_current_line():sub(1, get_current_col() - 1)
    return small_del(
      start_of_line() and not first_line() and '\n'
        or line_before:match('%S') and line_before:gsub('^%s*', '')
        or line_before,
      false
    )
  end, { expr = true, desc = 'Delete text until the beginning of the line' })

  map('c', '<C-y>', [[pumvisible() ? '<C-y>' : '<C-r>-']], {
    expr = true,
    desc = 'Confirm completion or paste from small deletion register',
  })
  map('i', '<C-y>', function()
    if fn.pumvisible() == 1 then
      api.nvim_feedkeys(vim.keycode('<C-y>'), 'n', false)
      return
    end

    local linenr = line('.')
    local colnr = col('.')
    local current_line = api.nvim_get_current_line()
    local lines = vim.split(fn.getreg('-'), '\n')
    lines[1] = current_line:sub(1, colnr - 1) .. lines[1]
    local target_cursor = { linenr + #lines - 1, #lines[#lines] }
    lines[#lines] = lines[#lines] .. current_line:sub(colnr)

    api.nvim_feedkeys(vim.keycode('<C-g>u'), 'n', false)
    api.nvim_buf_set_lines(0, linenr - 1, linenr, false, lines)
    api.nvim_win_set_cursor(0, target_cursor)
  end, { desc = 'Confirm completion or paste from small deletion register' })

  map('!', '<C-a>', function()
    local current_line = get_current_line()
    return '<Home>'
      .. (
        current_line:sub(1, get_current_col() - 1):match('%S')
          and string.rep('<Right>', #current_line:match('^%s*'))
        or ''
      )
  end, { expr = true, desc = 'Go to the beginning of the line' })

  map('!', '<C-e>', function()
    return fn.pumvisible() == 1 and '<C-e>' or '<End>'
  end, {
    expr = true,
    desc = 'Cancel completion or go to the end of the line',
  })

  map('i', '<C-b>', function()
    if first_line() and start_of_line() then
      return '<Ignore>'
    end
    return start_of_line() and '<Up><End>' or '<Left>'
  end, {
    expr = true,
    desc = 'Move cursor backward',
  })

  map('i', '<C-f>', function()
    if last_line() and end_of_line() then
      return '<Ignore>'
    end
    return end_of_line() and '<Down><Home>' or '<Right>'
  end, {
    expr = true,
    desc = 'Move cursor forward',
  })

  map('!', '<M-b>', function()
    local word_before = get_word_before()
    if not str_isempty(word_before) or fn.mode() == 'c' then
      return string.rep('<Left>', #word_before)
    end
    -- No word before cursor and is in insert mode
    local current_linenr = line('.')
    local target_linenr = fn.prevnonblank(current_linenr - 1)
    target_linenr = target_linenr ~= 0 and target_linenr or 1
    local line_str = fn.getline(target_linenr) --[[@as string]]
    return (current_linenr == target_linenr and '' or '<End>')
      .. string.rep('<Up>', current_linenr - target_linenr)
      .. string.rep('<Left>', #get_word_before(line_str, #line_str))
  end, {
    expr = true,
    desc = 'Move cursor backward by word',
  })

  map('!', '<M-f>', function()
    local word_after = get_word_after()
    if not str_isempty(word_after) or fn.mode() == 'c' then
      return string.rep('<Right>', #word_after)
    end
    -- No word after cursor and is in insert mode
    local current_linenr = line('.')
    local target_linenr = fn.nextnonblank(current_linenr + 1)
    target_linenr = target_linenr ~= 0 and target_linenr or line('$')
    local line_str = fn.getline(target_linenr) --[[@as string]]
    return (current_linenr == target_linenr and '' or '<Home>')
      .. string.rep('<Down>', target_linenr - current_linenr)
      .. string.rep('<Right>', #get_word_after(line_str, 1))
  end, {
    expr = true,
    desc = 'Move cursor forward by word',
  })
end

return M
