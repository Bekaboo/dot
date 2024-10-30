local api = vim.api
local utils = require('utils')

local lowercase_words = {
  ['a'] = true,
  ['an'] = true,
  ['and'] = true,
  ['as'] = true,
  ['at'] = true,
  ['but'] = true,
  ['by'] = true,
  ['for'] = true,
  ['if'] = true,
  ['in'] = true,
  ['nor'] = true,
  ['of'] = true,
  ['off'] = true,
  ['on'] = true,
  ['or'] = true,
  ['per'] = true,
  ['so'] = true,
  ['the'] = true,
  ['than'] = true,
  ['to'] = true,
  ['up'] = true,
  ['via'] = true,
  ['vs'] = true,
  ['yet'] = true,
}

---@type bufopt_t
local opt_captitle = utils.classes.bufopt_t:new('captitle', true)

---Capitalize the first letter of words on title line
---@param info table information given to event handler
---@return nil
local function format_title(info)
  if vim.bo[info.buf].filetype ~= 'markdown' or not opt_captitle:get() then
    return
  end

  local cursor = api.nvim_win_get_cursor(0)
  local line = api.nvim_get_current_line()
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

  local word_lower = word:lower()
  if word_lower ~= word and lowercase_words[word_lower] then
    line = line:sub(1, cursor[2] - #word)
      .. word_lower
      .. line:sub(cursor[2] + 1)
    api.nvim_set_current_line(line)
    return
  end

  local word_cap = word:sub(1, 1):upper() .. word:sub(2)
  if word_cap ~= word and not lowercase_words[word_lower] then
    line = line:sub(1, cursor[2] - #word)
      .. word_cap
      .. line:sub(cursor[2] + 1)
    api.nvim_set_current_line(line)
    return
  end
end

local buf = vim.api.nvim_get_current_buf()
api.nvim_create_autocmd('TextChangedI', {
  group = api.nvim_create_augroup('MarkdownAutoFormatTitle' .. buf, {}),
  buffer = buf,
  callback = format_title,
})

api.nvim_buf_create_user_command(buf, 'MarkdownSetCapTitle', function(info)
  local parsed_args = utils.command.parse_cmdline_args(info.fargs)
  if info.bang then
    return opt_captitle:scope_action(parsed_args, 'toggle')
  end
  if info.fargs[1] == '&' then
    return opt_captitle:scope_action(parsed_args, 'reset')
  end
  if info.fargs[1] == '?' then
    return opt_captitle:scope_action(parsed_args, 'print')
  end
  if vim.tbl_contains(parsed_args, 'enable') then
    return opt_captitle:scope_action(parsed_args, 'set', true)
  end
  if vim.tbl_contains(parsed_args, 'disable') then
    return opt_captitle:scope_action(parsed_args, 'set', false)
  end
end, {
  nargs = '*',
  bang = true,
  complete = utils.command.complete({
    'enable',
    'disable',
  }, {
    ['global'] = { 'v:true', 'v:false' },
    ['local'] = { 'v:true', 'v:false' },
  }),
  desc = 'Set whether to automatically capitalize the first letter of words in markdown titles',
})
