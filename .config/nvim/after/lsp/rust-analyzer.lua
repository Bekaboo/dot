---@type lsp_config_t
return {
  filetypes = { 'rust' },
  cmd = { 'rust-analyzer' },
  root_markers = { 'Cargo.toml' },
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
    -- https://github.com/rust-lang/rust-analyzer/blob/eb5da56d839ae0a9e9f50774fa3eb78eb0964550/docs/dev/lsp-extensions.md?plain=1#L26
    if config.settings then
      params.initializationOptions = config.settings['rust-analyzer']
    end
  end,
}
