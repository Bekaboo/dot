local config_file = '~/.markdownlint-cli2.cjs'
local config_arg = ''

if (vim.uv.fs_stat(vim.fs.normalize(config_file)) or {}).type == 'file' then
  config_arg = '--config ' .. config_file
end

local format_command = ('markdownlint-cli2 %s --format'):format(config_arg)
local lint_command = ('markdownlint-cli2 %s -'):format(config_arg)

---@type my.lsp.config
return {
  filetypes = { 'markdown' },
  cmd = { 'efm-langserver' },
  requires = { 'markdownlint-cli2' },
  name = 'markdownlint-cli2',
  init_options = {
    documentFormatting = true,
  },
  settings = {
    languages = {
      markdown = {
        {
          formatCommand = format_command,
          formatStdin = true,
        },
        {
          lintSource = 'markdownlint-cli2',
          lintCommand = lint_command,
          lintFormats = {
            '%f:%l %trror %m',
            '%f:%l %tarning %m',
          },
          lintAfterOpen = true,
          lintStdin = true,
          lintIgnoreExitCode = true,
        },
      },
    },
  },
}
