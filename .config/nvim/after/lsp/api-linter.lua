-- Google api-linter, see: https://linter.aip.dev

local root_markers = { 'apilint.yaml' }

return {
  filetypes = { 'proto' },
  cmd = { 'efm-langserver' },
  requires = { 'api-linter' },
  name = 'api-linter',
  root_markers = root_markers,
  settings = {
    languages = {
      proto = {
        {
          lintSource = 'api-linter',
          lintCommand = 'api-linter --config apilint.yaml "${INPUT}" || api-lint "${INPUT}"',
          lintFormats = { '%[0-9/]\\+ %[0-9:]\\+ %f:%l:%c: %m' },
          lintStdin = false,
          lintSeverity = vim.log.levels.INFO,
          rootMarkers = vim.iter(root_markers):flatten():totable(),
        },
      },
    },
  },
}
