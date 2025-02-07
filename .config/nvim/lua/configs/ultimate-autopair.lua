local ap_utils = require('ultimate-autopair.utils')
local ap_core = require('ultimate-autopair.core')

---Filetype options memoization
---@type table<string, table<string, string|integer|boolean|table>>
local ft_opts = vim.defaulttable(function()
  return {}
end)

---Get option value for given filetype, with memoization for performance
---This fixes sluggish `<CR>` in markdown files
---TODO: upstream to ultimate-autopair
---@param ft string
---@param opt string
---@diagnostic disable-next-line: duplicate-set-field
ap_utils.ft_get_option = function(ft, opt)
  local opts = ft_opts[ft]
  local opt_val = opts[opt]
  if opt_val ~= nil then
    return opt_val
  end

  opt_val = vim.F.npcall(vim.filetype.get_option, ft, opt) or vim.bo[opt]
  opts[opt] = opt_val
  return opt_val
end

ap_utils.getsmartft = (function(cb)
  return function(o, notree, ...)
    return cb(o, vim.b.bigfile or notree, ...)
  end
end)(ap_utils.getsmartft)

-- Set 'lazyredraw' on paring to prevent cursor jump caused by `<C-g>U<Left>`
-- Source: https://github.com/windwp/nvim-autopairs/pull/403
-- TODO: upstream
ap_core.run_run = (function(cb)
  local lz

  return function(...)
    if not vim.go.lz then
      lz = vim.go.lz
      vim.go.lz = true

      vim.schedule(function()
        if lz == nil then
          return
        end
        vim.go.lz = lz
        lz = nil
      end)
    end

    return cb(...)
  end
end)(ap_core.run_run)

---Get next two characters after cursor
---@return string: next two characters
local function get_suffix()
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

require('ultimate-autopair').setup({
  extensions = {
    suround = false,
    -- Improve performance when typing fast, see
    -- https://github.com/altermo/ultimate-autopair.nvim/issues/74
    utf8 = false,
    cond = {
      cond = function(f)
        -- Disable autopairs when inserting a regex,
        -- e.g. `:s/{pattern}/{string}/[flags]` or
        -- `:g/{pattern}/[cmd]`, etc.
        if f.in_cmdline() then
          return compltype[2] ~= 'command' or compltype[1] ~= ''
        end

        return not f.in_macro()
          -- Disable autopairs if followed by a keyword or an opening pair
          and not IGNORE_REGEX:match_str(get_suffix())
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

local has_cmp, cmp = pcall(require, 'cmp')
if has_cmp then
  local format = require('cmp.config').get().formatting.format
  cmp.setup({
    formatting = {
      format = function(entry, item)
        -- Don't complete left parenthesis when calling functions or
        -- expressions in cmdline, e.g. `:call func(...`
        local type = compltype[1]
        if type == 'function' or type == 'expression' then
          item.word = string.gsub(item.word, '%($', '')
          item.abbr = item.word
        end
        return format(entry, item)
      end,
    },
  })
end
