---Neovim integration with `aider` cli

local M = {}

---Toggle aider at `path`
---@param path? string path to a project or a project file
function M.toggle(path)
  local chat = require('plugin.aider.chat').get(path)
  if chat then
    chat:toggle()
  end
end

---Enter insert/terminal mode
---`:startinsert` does not work in line-wise or block-wise visual mode
local function startinsert()
  vim.api.nvim_feedkeys(vim.keycode('<C-\\><C-n>i'), 'n', false)
end

---Add file to aider
---@param path? string file path to add, default to current file
function M.add_file(path)
  path = path or vim.api.nvim_buf_get_name(0)
  if vim.fn.filereadable(path) == 0 then
    vim.notify(string.format("[aider] '%s' is not a readable file", path))
    return
  end

  local chat = require('plugin.aider.chat').get(path)
  if not chat then
    return
  end

  chat:send('/add ' .. chat:reduce_path(path))
  chat:open()
  startinsert()
end

---Send selected text to aider at `path`
---Supposed to be called in visual mode
---@param path? string path to a project or a project file
function M.send_sel(path)
  local chat = require('plugin.aider.chat').get(path)
  if not chat then
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local sel = vim.fn.getregion(
    vim.fn.getpos('.'),
    vim.fn.getpos('v'),
    { type = string.sub(vim.fn.mode(), 1, 1) }
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
  startinsert()
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
end

return M
