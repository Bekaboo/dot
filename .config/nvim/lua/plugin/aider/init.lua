---Neovim integration with `aider` cli

local M = {}

---@param path? string path to a project or a project file
function M.toggle(path)
  local chat = require('plugin.aider.chat').get(path)
  if chat then
    chat:toggle()
  end
end

---@param opts aider_opts_t
function M.setup(opts)
  if vim.g.loaded_aider ~= nil then
    return
  end
  vim.g.loaded_aider = true

  local configs = require('plugin.aider.configs')
  if not configs.set(opts) then
    return
  end

  if configs.opts.watch.enabled then
    require('plugin.aider.watch').watch()
  end
end

return M
