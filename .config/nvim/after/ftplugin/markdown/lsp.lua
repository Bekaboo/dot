local lsp = require('utils.lsp')

local server_configs = {
  {
    cmd = { 'marksman' },
    root_patterns = { '.marksman.toml' },
  },
  {
    cmd = { 'markdown-oxide' },
    root_patterns = { '.moxide.toml' },
    on_attach = function()
      vim.api.nvim_buf_create_user_command(0, 'Today', function()
        vim.lsp.buf.execute_command({
          command = 'jump',
          arguments = { 'today' },
        })
      end, { desc = "Open today's daily note" })
      vim.api.nvim_buf_create_user_command(0, 'Yesterday', function()
        vim.lsp.buf.execute_command({
          command = 'jump',
          arguments = { 'yesterday' },
        })
      end, { desc = "Open yesterday's daily note" })
      vim.api.nvim_buf_create_user_command(0, 'Tomorrow', function()
        vim.lsp.buf.execute_command({
          command = 'jump',
          arguments = { 'tomorrow' },
        })
      end, { desc = "Open tomorrow's daily note" })
    end,
  },
}

for _, server_config in ipairs(server_configs) do
  if lsp.start(server_config) then
    return
  end
end
