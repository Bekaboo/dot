local M = {}

---Set up VSCode-Neovim integration
function M.setup()
  vim.fn['my#plugin#vscode#setup']()
end

return M
