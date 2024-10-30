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
})
