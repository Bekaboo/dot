require('utils.lsp').start({
  cmd = { 'rust-analyzer' },
  root_patterns = { 'Cargo.toml' },
  settings = {
    ['rust-analyzer'] = {
      imports = {
        prefix = 'self',
        granularity = { group = 'module' },
      },
      cargo = { buildScripts = { enable = true } },
      procMacro = { enable = true },
    },
  },
  capabilities = {
    experimental = {
      serverStatusNotification = true,
    },
  },
  before_init = function(params, config)
    -- See https://github.com/rust-lang/rust-analyzer/blob/eb5da56d839ae0a9e9f50774fa3eb78eb0964550/docs/dev/lsp-extensions.md?plain=1#L26
    if config.settings then
      params.initializationOptions = config.settings['rust-analyzer']
    end
  end,
  -- Source: https://github.com/neovim/nvim-lspconfig/blob/master/lua/lspconfig/configs/rust_analyzer.lua
  on_attach = function(client)
    vim.api.nvim_buf_create_user_command(0, 'CargoReload', function()
      client.request('rust-analyzer/reloadWorkspace', nil, function(err)
        if err then
          vim.notify('Corresponding reload cargo workspace: ' .. tostring(err))
          return
        end
        vim.notify('Cargo workspace reloaded')
      end, 0)
    end, { description = 'Reload current cargo workspace' })
  end,
})
