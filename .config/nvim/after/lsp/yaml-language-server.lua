-- Language server for YAML files
-- https://github.com/redhat-developer/yaml-language-server

return {
  filetypes = { 'yaml' },
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
