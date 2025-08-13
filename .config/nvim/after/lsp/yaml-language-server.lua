-- Language server for YAML files
-- https://github.com/redhat-developer/yaml-language-server

---@type lsp_config_t
return {
  filetypes = { 'yaml', 'yaml.gh' },
  cmd = {
    'yaml-language-server',
    '--stdio',
  },
  settings = {
    -- Don't send telemetry to redhat
    -- https://github.com/redhat-developer/vscode-redhat-telemetry#how-to-disable-telemetry-reporting
    redhat = {
      telemetry = {
        enabled = false,
      },
    },
  },
}
