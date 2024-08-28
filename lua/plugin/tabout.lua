local fmt = string.format

---@class fallbak_tbl_t each key shares a default / fallback pattern table
---that can be used for pattern matching if corresponding key is not present
---or non patterns stored in the key are matched
---@field __content table closing patterns for each filetype
---@field __default table
local fallback_tbl_t = {}

function fallback_tbl_t:__index(k)
  return fallback_tbl_t[k] or self:fallback(k)
end

function fallback_tbl_t:__newindex(k, v)
  self.__content[k] = v
end

---Get the table with the fallback patterns for kdest
---@param k string key
---@return table concatenated table
function fallback_tbl_t:fallback(k)
  local dest = self.__content[k]
  local default = self.__default
  if dest and default then
    if vim.islist(dest) and vim.islist(default) then
      return vim.list_extend(dest, default)
    else
      dest = vim.tbl_deep_extend('keep', dest, default)
      return dest
    end
  elseif dest then
    return dest
  elseif default then
    return default
  end
  return {}
end

---Create a new shared table
---@param args table
---@return fallbak_tbl_t
function fallback_tbl_t:new(args)
  args = args or {}
  local fallback_tbl = {
    __content = args.content or {},
    __default = args.default or {},
  }
  return setmetatable(fallback_tbl, self)
end

-- stylua: ignore start
local patterns = fallback_tbl_t:new({
  default = {
    '\\%)',
    '\\%)',
    '\\%]',
    '\\}',
    '%)',
    '%]',
    '}',
    '"',
    "'",
    '`',
    ',',
    ';',
    '%.',
  },
  content = {
    c = { '%*/' },
    cpp = { '%*/' },
    cuda = { '>>>' },
    lua = { '%]=*%]' },
    python = { '"""', "'''" },
    html = { '<[^>]*>' },
    xml = { '<[^>]*>' },
    markdown = {
      '\\right\\rfloor',
      '\\right\\rceil',
      '\\right\\vert',
      '\\right\\Vert',
      '\\right%)',
      '\\right%]',
      '\\right}',
      '\\right>',
      '\\%]',
      '\\}',
      '-->',
      '<[^>]*>',
      '%*%*%*',
      '%*%*',
      '%*',
      '%$',
      '|',
    },
    tex = {
      '\\right\\rfloor',
      '\\right\\rceil',
      '\\right\\vert',
      '\\right\\Vert',
      '\\right%)',
      '\\right%]',
      '\\right}',
      '\\right>',
      '\\%]',
      '\\}',
      '%$',
    },
  },
})

local opening_pattern_lookup_tbl = {
  ["'"]               = "'",
  ['"']               = '"',
  [',']               = '.',
  [';']               = '.',
  ['`']               = '`',
  ['|']               = '|',
  ['}']               = '{',
  ['%.']              = '.',
  ['%$']              = '%$',
  ['%)']              = '%(',
  ['%]']              = '%[',
  ['%*']              = '%*',
  ['<<<']             = '>>>',
  ['%*%*']            = '%*%*',
  ['%*%*%*']          = '%*%*%*',
  ['"""']             = '"""',
  ["'''"]             = "'''",
  ['%*/']             = '/%*',
  ['\\}']             = '\\{',
  ['-->']             = '<!--',
  ['\\%)']            = '\\%(',
  ['\\%]']            = '\\%[',
  ['%]=*%]']          = '--%[=*%[',
  ['<[^>]*>']         = '<[^>]*>',
  ['\\right}']        = '\\left{',
  ['\\right>']        = '\\left<',
  ['\\right%)']       = '\\left%(',
  ['\\right%]']       = '\\left%[',
  ['\\right\\vert']   = '\\left\\vert',
  ['\\right\\Vert']   = '\\left\\lVert',
  ['\\right\\rceil']  = '\\left\\lceil',
  ['\\right\\rfloor'] = '\\left\\lfloor',
}
-- stylua: ignore end

---Get the index where Shift-Tab should jump to
---1. If there is only whitespace characters or no character in between
---   the opening and closing pattern, jump to the end of the whitespace
---   characters (i.e. right before the closing pattern)
---
---       1.1. Special case: if there is exactly two whitespace characters,
---            jump to the middle of the two whitespace characters
---
---2. If there is contents (non-whitespace characters) in between the
---   opening and closing pattern, jump to the end of the contents
---@param leading any leading texts on current line
---@param closing_pattern any closing pattern
---@param cursor number[] cursor position
---@return number[] cursor position after jump
local function jumpin_idx(leading, closing_pattern, cursor)
  local opening_pattern = opening_pattern_lookup_tbl[closing_pattern]

  -- Case 1
  local _, _, content_str, closing_pattern_str =
    leading:find(fmt('%s(%s)(%s)$', opening_pattern, '%s*', closing_pattern))
  if content_str == nil or closing_pattern_str == nil then
    _, _, content_str, closing_pattern_str =
      leading:find(fmt('^(%s)(%s)$', '%s*', closing_pattern))
  end

  if content_str and closing_pattern_str then
    -- Case 1.1
    if #content_str == 2 then
      return { cursor[1], cursor[2] - #closing_pattern_str - 1 }
    else
      return { cursor[1], cursor[2] - #closing_pattern_str }
    end
  end

  -- Case 2
  _, _, _, closing_pattern_str = leading:find(
    fmt(
      '%s%s(%s)$',
      opening_pattern .. '%s*',
      '.*%S',
      '%s*' .. closing_pattern .. '%s*'
    )
  )

  if content_str == nil or closing_pattern_str == nil then
    _, _, closing_pattern_str =
      leading:find(fmt('%s(%s)$', '%S', '%s*' .. closing_pattern .. '%s*'))
  end

  return { cursor[1], cursor[2] - #closing_pattern_str }
end

---Check if the cursor is in cmdline
---@return boolean
local function in_cmdline()
  return vim.fn.mode():match('^c') ~= nil
end

---Get the cursor position, whether in cmdline or normal buffer
---@return number[] cursor: 1,0-indexed cursor position
local function get_cursor()
  return in_cmdline() and { 1, vim.fn.getcmdpos() - 1 }
    or vim.api.nvim_win_get_cursor(0)
end

---Get current line, whether in cmdline or normal buffer
---@return string current_line: current line
local function get_line()
  return in_cmdline() and vim.fn.getcmdline()
    or vim.api.nvim_get_current_line()
end

---Getting the jump position for Tab
---@return number[]? cursor position after jump; nil if no jump
local function get_tabout_pos()
  local cursor = get_cursor()
  local current_line = get_line()
  local trailing = current_line:sub(cursor[2] + 1, -1)
  local leading = current_line:sub(1, cursor[2])

  -- Do not jump if the cursor is at the beginning/end of the current line
  if leading:match('^%s*$') or trailing == '' then
    return
  end

  for _, pattern in ipairs(patterns[vim.bo.ft or '']) do
    local _, jump_pos = trailing:find('^%s*' .. pattern)
    if jump_pos then
      return { cursor[1], cursor[2] + jump_pos }
    end
  end
end

---Getting the jump position for Shift-Tab
---@return number[]? cursor position after jump; nil if no jump
local function get_tabin_pos()
  local cursor = get_cursor()
  local current_line = get_line()
  local leading = current_line:sub(1, cursor[2])

  for _, pattern in ipairs(patterns[vim.bo.ft or '']) do
    local _, closing_pattern_end = leading:find(pattern .. '%s*$')
    if closing_pattern_end then
      return jumpin_idx(leading:sub(1, closing_pattern_end), pattern, cursor)
    end
  end
end

---@param direction 1|-1 1 for tabout, -1 for tabin
---@return number[]? cursor position after jump; nil if no jump
local function get_jump_pos(direction)
  if direction == 1 then
    return get_tabout_pos()
  else
    return get_tabin_pos()
  end
end

local RIGHT = vim.api.nvim_replace_termcodes('<Right>', true, true, true)
local LEFT = vim.api.nvim_replace_termcodes('<Left>', true, true, true)

---Set the cursor position, whether in cmdline or normal buffer
---@param pos number[] cursor position
---@return nil
local function set_cursor(pos)
  if in_cmdline() then
    local cursor = get_cursor()
    local diff = pos[2] - cursor[2]
    local termcode = string.rep(diff > 0 and RIGHT or LEFT, math.abs(diff))
    vim.api.nvim_feedkeys(termcode, 'nt', true)
  else
    vim.api.nvim_win_set_cursor(0, pos)
  end
end

local TAB = vim.api.nvim_replace_termcodes('<Tab>', true, true, true)
local S_TAB = vim.api.nvim_replace_termcodes('<S-Tab>', true, true, true)

---Get the position to jump for Tab or Shift-Tab, perform the jump if
---there is a position to jump to, otherwise fallback (feedkeys)
---@param direction 1|-1 1 for tabout, -1 for tabin
local function jump(direction)
  local pos = get_jump_pos(direction)
  if pos then
    set_cursor(pos)
    return
  end
  vim.api.nvim_feedkeys(direction == 1 and TAB or S_TAB, 'nt', false)
end

return {
  jump = jump,
  get_jump_pos = get_jump_pos,
}
