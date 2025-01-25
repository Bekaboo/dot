local lsp = require('utils.lsp')

---@param client vim.lsp.Client
local function symbol_info(client)
  local bufnr = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  client.request(
    'textDocument/symbolInfo',
    vim.lsp.util.make_position_params(win, client.offset_encoding),
    function(err, res)
      -- Clangd always returns an error, there is not reason to parse it
      if err or #res == 0 then
        return
      end
      local container = string.format('container: %s', res[1].containerName)
      local name = string.format('name: %s', res[1].name)
      vim.lsp.util.open_floating_preview({ name, container }, '', {
        height = 2,
        width = math.max(string.len(name), string.len(container)),
        focusable = false,
        focus = false,
      })
    end,
    bufnr
  )
end

---@param client vim.lsp.Client
local function switch_source_header(client)
  local method_name = 'textDocument/switchSourceHeader'
  local buf = vim.api.nvim_get_current_buf()
  client.request(
    method_name,
    vim.lsp.util.make_text_document_params(buf),
    function(err, result)
      if err or not result then
        vim.notify(
          string.format(
            '[%s] Corresponding file cannot be determined',
            client.name
          )
        )
        if err then
          vim.notify('Error: ' .. err)
        end
        return
      end
      vim.cmd.edit(vim.uri_to_fname(result))
    end,
    buf
  )
end

local server_configs = {
  {
    cmd = { 'clangd' },
    root_patterns = {
      '.clangd',
      '.clang-tidy',
      '.clang-format',
      'compile_commands.json',
      'compile_flags.txt',
      'configure.ac',
    },
    on_attach = function(client)
      vim.api.nvim_buf_create_user_command(0, 'ClangdSymbolInfo', function()
        symbol_info(client)
      end, { desc = 'Show c/cpp symbol info' })
      vim.api.nvim_buf_create_user_command(
        0,
        'ClangdSwitchSourceHeader',
        function()
          switch_source_header(client)
        end,
        { desc = 'Switch between c/cpp source/header' }
      )
    end,
  },
  {
    cmd = { 'ccls' },
    root_patterns = { '.ccls', 'compile_commands.json' },
    on_attach = function(client)
      vim.api.nvim_buf_create_user_command(
        0,
        'CclsSwitchSourceHeader',
        function()
          switch_source_header(client)
        end,
        { desc = 'Switch between c/cpp source/header' }
      )
    end,
  },
}

for _, server_config in ipairs(server_configs) do
  if lsp.start(server_config) then
    return
  end
end
