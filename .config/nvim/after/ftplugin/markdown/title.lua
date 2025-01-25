local utils = require('utils')

if vim.g.md_fmt_title == nil then
  vim.g.md_fmt_title = true
end

-- Export the word list to global so that other parts of the config
-- (e.g. markdown snippets) can access it
_G._title_lowercase_words = {
  ['a'] = true,
  ['an'] = true,
  ['and'] = true,
  ['as'] = true,
  ['at'] = true,
  ['but'] = true,
  ['by'] = true,
  ['can'] = true,
  ['etc'] = true,
  ['for'] = true,
  ['if'] = true,
  ['in'] = true,
  ['is'] = true,
  ['nor'] = true,
  ['of'] = true,
  ['off'] = true,
  ['on'] = true,
  ['or'] = true,
  ['per'] = true,
  ['so'] = true,
  ['than'] = true,
  ['the'] = true,
  ['to'] = true,
  ['up'] = true,
  ['via'] = true,
  ['vs'] = true,
  ['was'] = true,
  ['were'] = true,
  ['with'] = true,
  ['yet'] = true,
}

---Capitalize the first letter of words on title line
---@return nil
local function format_title()
  if
    vim.bo.filetype ~= 'markdown'
    or vim.b.md_fmt_title == false
    or (vim.g.md_fmt_title == false and vim.b.md_fmt_title == nil)
  then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local lnum = vim.fn.line('.')
  if
    not line:match('^#+%s')
    or utils.ft.markdown.in_codeblock(lnum)
    or utils.ft.markdown.in_codeinline(cursor)
  then
    return
  end

  local word = line:sub(1, cursor[2]):match('[%w_]+$')
  if word == nil then
    return
  end

  local is_first = line:match('^#+%s+([%w_]+)$') == word
  local should_upper = is_first
    or not (_G._title_lowercase_words[word:lower()] or #word < 3)

  if should_upper then
    local word_upper = word:sub(1, 1):upper() .. word:sub(2)
    if word_upper ~= word then
      vim.api.nvim_buf_set_text(
        0,
        cursor[1] - 1,
        cursor[2] - #word,
        cursor[1] - 1,
        cursor[2],
        { word_upper }
      )
    end
  end
end

local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_create_autocmd('TextChangedI', {
  group = vim.api.nvim_create_augroup('MarkdownAutoFormatTitle' .. buf, {}),
  buffer = buf,
  callback = format_title,
})

vim.api.nvim_buf_create_user_command(
  buf,
  'MarkdownAutoFormatTitle',
  function(args)
    local parsed_args = utils.cmd.parse_cmdline_args(args.fargs)
    local scope = vim[parsed_args.global and 'g' or 'b']
    if scope.md_fmt_title == nil then
      scope.md_fmt_title = vim.g.md_fmt_title
    end
    if args.bang or vim.tbl_contains(parsed_args, 'toggle') then
      scope.md_fmt_title = not scope.md_fmt_title
      return
    end
    if args.fargs[1] == '&' or vim.tbl_contains(parsed_args, 'reset') then
      scope.md_fmt_title = true
      return
    end
    if args.fargs[1] == '?' or vim.tbl_contains(parsed_args, 'status') then
      vim.notify(tostring(scope.md_fmt_title))
      return
    end
    if vim.tbl_contains(parsed_args, 'enable') then
      scope.md_fmt_title = true
      return
    end
    if vim.tbl_contains(parsed_args, 'disable') then
      scope.md_fmt_title = false
      return
    end
  end,
  {
    nargs = '*',
    bang = true,
    complete = utils.cmd.complete({
      'enable',
      'disable',
      'toggle',
      'status',
    }, {
      ['global'] = { 'v:true', 'v:false' },
      ['local'] = { 'v:true', 'v:false' },
    }),
    desc = 'Set whether to automatically capitalize the first letter of words in markdown titles',
  }
)
