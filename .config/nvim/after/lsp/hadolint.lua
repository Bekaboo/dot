-- Dockerfile linter, validate inline bash, written in Haskell
-- https://github.com/hadolint/hadolint

---@type lsp_config_t
return {
  filetypes = { 'dockerfile' },
  cmd = { 'efm-langserver' },
  requires = { 'hadolint' },
  name = 'hadolint',
  root_markers = { '.hadolint.yaml' },
  settings = {
    languages = {
      dockerfile = {
        {
          lintSource = 'hadolint',
          lintCommand = 'hadolint --format gnu ${INPUT}',
          lintFormats = {
            'hadolint:%f:%l: SC%n %t%\\w\\+: %m',
          },
          lintStdin = false,
          lintOffset = -1,
          lintAfterOpen = true,
        },
      },
    },
  },
}
