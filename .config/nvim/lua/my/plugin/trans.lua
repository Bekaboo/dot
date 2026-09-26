local M = {}

---@alias my.trans.winopt.value boolean|integer|string|table
---@alias my.trans.winopt my.trans.winopt.value|fun(lines: string[], source_win: integer, source_pos: [integer, integer], resolved_winopts: table<string, my.trans.winopt.value>): my.trans.winopt.value

---@class my.trans.config.opts
---@field pair? string
---@field to? string
---@field winopts table<string, my.trans.winopt>

---@type my.trans.config.opts
local config = {
  winopts = {
    relative = 'cursor',
    style = 'minimal',
    border = 'solid',
    row = 1,
    col = 0,
    ---Calculate the float width from its contents
    width = function(lines)
      local width = 1
      for _, line in ipairs(lines) do
        width = math.max(width, vim.fn.strdisplaywidth(line))
      end
      local min_width = vim.go.pumwidth > 0 and vim.go.pumwidth or nil
      local max_width = math.max(80, math.ceil(vim.go.columns * 0.75))
      return math.min(
        math.max(width, min_width or width),
        max_width,
        vim.go.columns - 2
      )
    end,
    ---Calculate the float height from its contents and resolved width
    height = function(lines, _, _, resolved_winopts)
      local width = resolved_winopts.width --[[@as integer]]
      local height = 0
      for _, line in ipairs(lines) do
        height = height
          + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
      end
      local min_height = 1
      local max_height = math.max(20, math.ceil(vim.go.lines * 0.4))
      return math.min(
        math.max(height, min_height),
        max_height,
        vim.go.lines - 2
      )
    end,
  },
}

---Evaluate a static or callable floating-window option
---@param opt my.trans.winopt
---@param lines string[]
---@param source_win integer
---@param source_pos [integer, integer]
---@param resolved_winopts table<string, my.trans.winopt.value>
---@return my.trans.winopt.value
local function eval_winopt(
  opt,
  lines,
  source_win,
  source_pos,
  resolved_winopts
)
  if vim.is_callable(opt) then
    return opt(lines, source_win, source_pos, resolved_winopts)
  end
  ---@cast opt my.trans.winopt.value
  return opt
end

---Resolve configured floating-window options
---@param lines string[]
---@param source_win integer
---@param source_pos [integer, integer]
---@return vim.api.keyset.win_config
local function eval_winopts(lines, source_win, source_pos)
  local resolved = {} ---@type table<string, my.trans.winopt.value>
  resolved.width =
    eval_winopt(config.winopts.width, lines, source_win, source_pos, resolved)
  for key, opt in pairs(config.winopts) do
    if key ~= 'width' and key ~= 'height' then
      resolved[key] = eval_winopt(opt, lines, source_win, source_pos, resolved)
    end
  end
  resolved.height =
    eval_winopt(config.winopts.height, lines, source_win, source_pos, resolved)
  return resolved --[[@as vim.api.keyset.win_config]]
end

---@class my.trans.cmd.parsed_args : my.cmd.parsed_args
---@field to? string

---@class my.trans.translate.opts
---@field text? string
---@field to? string

---Open and enter the translation floating window
---@param lines string[]
---@param source_win integer
---@param source_pos [integer, integer]
---@return integer buf
---@return integer win
local function open_float(lines, source_win, source_pos)
  if not vim.api.nvim_win_is_valid(source_win) then
    source_win = vim.api.nvim_get_current_win()
    source_pos = vim.api.nvim_win_get_cursor(source_win)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = true
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = vim.bo[vim.api.nvim_win_get_buf(source_win)].filetype

  local winopts = eval_winopts(lines, source_win, source_pos)
  local win = vim.api.nvim_open_win(buf, true, winopts)
  vim.wo[win].wrap = true
  return buf, win
end

---Update the translation contents and floating-window size
---@param buf integer
---@param win integer
---@param output string
---@param source_win integer
---@param source_pos [integer, integer]
local function update_float(buf, win, output, source_win, source_pos)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines = output == '' and { '' }
    or vim.split(output:gsub('\r\n', '\n'), '\n', { plain = true })
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  local winopts = eval_winopts(lines, source_win, source_pos)
  vim.api.nvim_win_set_config(win, {
    width = winopts.width,
    height = winopts.height,
  })
end

---Open a floating window to translate
---@param opts? my.trans.translate.opts
function M.translate(opts)
  opts = opts or {}
  local text = opts.text or vim.fn.expand('<cword>')
  if text == '' then
    vim.notify('[trans] no text to translate', vim.log.levels.WARN)
    return
  end

  local trans_cmd = { 'trans' }
  if config.pair then
    vim.list_extend(trans_cmd, { '--pair', config.pair })
  end
  local to = opts.to or config.to
  if to then
    vim.list_extend(trans_cmd, { '--to', to })
  end
  vim.list_extend(trans_cmd, { '--stream', '-' })

  local source_win = vim.api.nvim_get_current_win()
  local source_pos = vim.api.nvim_win_get_cursor(source_win)
  local float_buf, float_win = open_float({ '' }, source_win, source_pos)
  local output = ''
  local stdout_err
  vim.system(
    trans_cmd,
    {
      stdin = text,
      text = true,
      stdout = function(err, data)
        if err then
          stdout_err = err
          return
        end
        if not data then
          return
        end
        output = output .. data
        vim.schedule(function()
          update_float(float_buf, float_win, output, source_win, source_pos)
        end)
      end,
    },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 or stdout_err then
        local err = vim.trim(result.stderr or '')
        vim.notify(
          '[trans] '
            .. (
              stdout_err
              or err ~= '' and err
              or 'exited with code ' .. result.code
            ),
          vim.log.levels.ERROR
        )
        return
      end

      output = output:gsub('\r\n$', ''):gsub('\n$', '')
      if output:match('^%s*$') then
        vim.notify('[trans] returned no translation', vim.log.levels.WARN)
        return
      end
      update_float(float_buf, float_win, output, source_win, source_pos)
    end)
  )
end

---Set up the `:Translate` command
---@param opts my.trans.config.opts?
function M.setup(opts)
  if vim.g.loaded_trans ~= nil then
    return
  end
  vim.g.loaded_trans = true

  local cmd = require('my.utils.cmd')

  config = vim.tbl_deep_extend('force', config, opts or {})

  vim.api.nvim_create_user_command('Translate', function(args)
    local cmd_opts = cmd.parse_cmdline_args(args.fargs)
    M.translate({
      to = cmd_opts.to,
      text = (function()
        if args.range <= 0 then
          return
        end
        return table.concat(
          vim.api.nvim_buf_get_lines(0, args.line1 - 1, args.line2, false),
          '\n'
        )
      end)(),
    })
  end, {
    range = true,
    nargs = '*',
    complete = cmd.complete(nil, { 'to' }),
    desc = 'Translate the word under cursor or the given line range',
  })
end

return M
