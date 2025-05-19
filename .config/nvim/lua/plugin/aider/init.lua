---Neovim integration with `aider` cli

local M = {}

---Toggle aider at `path`
---@param path? string path to a project or a project file
function M.toggle(path)
  local chat = require('plugin.aider.chat'):get(path)
  if chat then
    chat:toggle()
  end
end

---Add file to aider
---@param path? string file path to add, default to current file
function M.add(path)
  path = path or vim.api.nvim_buf_get_name(0)
  if vim.fn.filereadable(path) == 0 then
    vim.notify(string.format("[aider] '%s' is not a readable file", path))
    return
  end

  local chat = require('plugin.aider.chat'):get(path)
  if not chat then
    return
  end

  chat:send('/add ' .. chat:reduce_path(path))
  chat:open()
  vim.cmd.startinsert()
end

---Send text in selected range to aider at `path`
---@param path? string path to a project or a project file
---@param range? integer[][] `getpos()`-like range consists of starting and ending pos, default to visual selection
function M.send(path, range)
  local chat = require('plugin.aider.chat'):get(path)
  if not chat then
    return
  end

  local buf = range and range[1] and range[1][1]
    or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local mode = vim.fn.mode()
  local sel = vim.fn.getregion(
    range and range[1] or vim.fn.getpos('.'),
    range and range[2] or vim.fn.getpos('v'),
    { type = mode:match('^[vV\x16]') and mode:sub(1, 1) or 'v' }
  )
  local msg = string.format(
    [[
Here are some contents from '%s':

```%s
%s
```

]],
    chat:reduce_path(vim.api.nvim_buf_get_name(buf)),
    vim.bo[buf].ft,
    table.concat(sel, '\n'):gsub('```', [[\`\`\`]])
  )

  chat:send(msg, buf)
  chat:open()

  -- Enter noraml mode first because `:startinsert` don't exit visual-line or
  -- visual-block mode
  vim.api.nvim_feedkeys(vim.keycode('<C-\\><C-n>i'), 'n', false)
end

---Return a command function
---@param cb fun(path: string?, range: integer[][]?)
---@return function
local function cmd(cb)
  return function(args)
    cb(
      args.args ~= '' and vim.fn.expand(args.args) or nil,
      not vim.fn.mode():match('^[vV\x16]')
          and {
            { 0, args.line1, 1, 0 },
            { 0, args.line2, 1, 0 },
          }
        or nil
    )
  end
end

---@param opts aider_opts_t
function M.setup(opts)
  if vim.g.loaded_aider ~= nil then
    return
  end
  vim.g.loaded_aider = true

  local configs = require('plugin.aider.configs')
  configs.set(opts)

  if configs.opts.watch.enabled then
    require('plugin.aider.watch').watch()
  end

  vim.api.nvim_create_user_command('Aider', cmd(M.toggle), {
    desc = 'Open aider.',
    complete = 'dir',
    nargs = '?',
  })
  vim.api.nvim_create_user_command('AiderAdd', cmd(M.add), {
    desc = 'Add file to aider.',
    complete = 'file',
    nargs = '?',
  })
  vim.api.nvim_create_user_command('AiderSend', cmd(M.send), {
    desc = 'Add file to aider.',
    complete = 'file',
    nargs = '?',
    range = true,
  })
end

return M
