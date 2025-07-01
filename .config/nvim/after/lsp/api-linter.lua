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
          lintCommand = 'if [ -f apilint.yaml ]; then api-linter --config apilint.yaml "${INPUT}"; else api-linter "${INPUT}"; fi',
          lintFormats = { '%[0-9/]%\\+ %[0-9:]%\\+ %f:%l:%c: %m' },
          lintStdin = false,
          lintSeverity = 3,
          rootMarkers = vim.iter(root_markers):flatten():totable(),
        },
      },
    },
  },
}
