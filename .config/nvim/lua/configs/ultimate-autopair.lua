local autopair_utils = require('ultimate-autopair.utils')
local _getsmartft = autopair_utils.getsmartft

---Always use `notree`
---Setting `opts.extensions.filetype.tree` to `false` does not always work
---There are multiple places where `getsmartft()` is called with `notree`
---omitted when it should be `true`
---TODO: report this bug to upstream
---@diagnostic disable-next-line: duplicate-set-field, unused-local
autopair_utils.getsmartft = function(o, _notree, ...)
  return _getsmartft(o, true, ...)
end

---Record previous cmdline completion types,
---`cmdcompltype[1]` is the current completion type,
---`cmdcompltype[2]` is the previous completion type
---@type string[]
local compltype = {}

vim.api.nvim_create_autocmd('CmdlineChanged', {
  desc = 'Record cmd compltype to determine whether to autopair.',
  group = vim.api.nvim_create_augroup('AutopairRecordCmdCompltype', {}),
  callback = function()
    local type = vim.fn.getcmdcompltype()
    if compltype[1] == type then
      return
    end
    compltype[2] = compltype[1]
    compltype[1] = type
  end,
})

---Get next two characters after cursor, whether in cmdline or normal buffer
---@return string: next two characters
local function get_next_two_chars()
  local col, line
  if vim.fn.mode():match('^c') then
    col = vim.fn.getcmdpos()
    line = vim.fn.getcmdline()
  else
    col = vim.fn.col('.')
    line = vim.api.nvim_get_current_line()
  end
  return line:sub(col, col + 1)
end

-- Matches strings that start with:
-- keywords: \k
-- opening pairs: (, [, {, \(, \[, \{
local IGNORE_REGEX = vim.regex([=[^\%(\k\|\\\?[([{]\)]=])

require('ultimate-autopair').setup({
  extensions = {
    suround = false,
    -- Improve performance when typing fast, see
    -- https://github.com/altermo/ultimate-autopair.nvim/issues/74
    utf8 = false,
    filetype = { tree = false },
    cond = {
      cond = function(f)
        return not f.in_macro()
          -- Disable autopairs if followed by a keyword or an opening pair
          and not IGNORE_REGEX:match_str(get_next_two_chars())
      end,
    },
  },
  { '\\(', '\\)' },
  { '\\[', '\\]' },
  { '\\{', '\\}' },
  { '[=[', ']=]', ft = { 'lua' } },
  { '<<<', '>>>', ft = { 'cuda' } },
  {
    '/*',
    '*/',
    ft = { 'c', 'cpp', 'cuda', 'go' },
    newline = true,
    space = true,
  },
  {
    '<',
    '>',
    disable_start = true,
    disable_end = true,
  },
  {
    '>',
    '<',
    ft = { 'html', 'xml', 'markdown' },
    disable_start = true,
    disable_end = true,
    newline = true,
    space = true,
  },
  -- Paring '$' and '*' are handled by snippets,
  -- only use autopair to delete matched pairs here
  {
    '$',
    '$',
    ft = { 'markdown', 'tex' },
    disable_start = true,
    disable_end = true,
  },
  {
    '*',
    '*',
    ft = { 'markdown' },
    disable_start = true,
    disable_end = true,
  },
  {
    '\\left(',
    '\\right)',
    newline = true,
    space = true,
    ft = { 'markdown', 'tex' },
  },
  {
    '\\left[',
    '\\right]',
    newline = true,
    space = true,
    ft = { 'markdown', 'tex' },
  },
  {
    '\\left{',
    '\\right}',
    newline = true,
    space = true,
    ft = { 'markdown', 'tex' },
  },
  {
    '\\left<',
    '\\right>',
    newline = true,
    space = true,
    ft = { 'markdown', 'tex' },
  },
  {
    '\\left\\lfloor',
    '\\right\\rfloor',
    newline = true,
    space = true,
    ft = { 'markdown', 'tex' },
  },
  {
    '\\left\\lceil',
    '\\right\\rceil',
    newline = true,
    space = true,
    ft = { 'markdown', 'tex' },
  },
  {
    '\\left\\vert',
    '\\right\\vert',
    newline = true,
    space = true,
    ft = { 'markdown', 'tex' },
  },
  {
    '\\left\\lVert',
    '\\right\\rVert',
    newline = true,
    space = true,
    ft = { 'markdown', 'tex' },
  },
  {
    '\\left\\lVert',
    '\\right\\rVert',
    newline = true,
    space = true,
    ft = { 'markdown', 'tex' },
  },
  {
    '\\begin{bmatrix}',
    '\\end{bmatrix}',
    newline = true,
    space = true,
    ft = { 'markdown', 'tex' },
  },
  {
    '\\begin{pmatrix}',
    '\\end{pmatrix}',
    newline = true,
    space = true,
    ft = { 'markdown', 'tex' },
  },
})
