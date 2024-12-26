---Get next two characters after cursor
---@return string: next two characters
local function get_next_two_chars()
  local col, line
  if vim.startswith(vim.fn.mode(), 'c') then
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
    cond = {
      cond = function(f)
        return not f.in_macro()
          -- Disable autopairs if followed by a keyword or an opening pair
          and not IGNORE_REGEX:match_str(get_next_two_chars())
      end,
    },
  },
  { '\\(', '\\)', newline = true },
  { '\\[', '\\]', newline = true },
  { '\\{', '\\}', newline = true },
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
  {
    '$',
    '$',
    ft = { 'markdown', 'tex' },
  },
  {
    '$$',
    '$$',
    newline = true,
    ft = { 'markdown', 'tex' },
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
