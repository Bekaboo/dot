-- Static checker for GitHub Actions workflow files
-- https://github.com/rhysd/actionlint/tree/v1.7.7

---@type lsp_config_t
return {
  -- Only attach to GitHub action/workflow YAML files, see
  -- `after/ftplugin/yaml.lua`
  filetypes = { 'yaml.gh' },
  cmd = { 'efm-langserver' },
  requires = { 'actionlint' },
  name = 'actionlint',
  root_markers = {
    'actionlint.yaml',
    'actionlint.yml',
  },
  settings = {
    languages = {
      ['yaml.gh'] = {
        {
          lintSource = 'actionlint',
          lintCommand = 'actionlint -oneline -',
          lintStdin = true,
          lintFormats = {
            '<stdin>:%l:%c: %m',
          },
        },
      },
    },
  },
}
