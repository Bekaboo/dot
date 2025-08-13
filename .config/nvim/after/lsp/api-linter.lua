-- Google api-linter, see: https://linter.aip.dev

---@type lsp_config_t
return {
  filetypes = { 'proto' },
  cmd = { 'efm-langserver' },
  requires = { 'api-linter', 'sed' },
  name = 'api-linter',
  root_markers = { 'apilint.yaml' },
  settings = {
    languages = {
      proto = {
        {
          lintSource = 'api-linter',
          lintCommand = [[
            if [ -f apilint.yaml ]; then
              config=--config apilint.yaml
            fi
            api-linter $config --output-format github "${INPUT}" | \
              sed 's/\\n/ /g' | \
              sed -E 's/ +/ /g';
          ]],
          lintFormats = {
            '::error file=%f,endLine=%\\d\\+,col=%c,line=%l,title=%m',
            '::error file=%f,title=%m',
          },
          -- Github format uses 0-based line and column numbers, use offset to
          -- convert them to 1-based for efm to mark error regions correctly
          lintOffset = -1,
          lintOffsetColumns = 1,
          lintIgnoreExitCode = true,
          lintAfterOpen = true,
          lintStdin = false,
          lintSeverity = 3,
        },
      },
    },
  },
}
