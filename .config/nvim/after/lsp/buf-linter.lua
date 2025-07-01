local root_markers = { 'buf.yaml' }

-- Currently buf's lsp implementation (`buf beta lsp`) is missing some
-- diagnostics from the linter (`buf lint`), so use efm-langserver to extract
-- and publish the diagnostics from `buf lint` command
return {
  filetypes = { 'proto' },
  cmd = { 'efm-langserver' },
  requires = { 'buf' },
  name = 'buf-linter',
  root_markers = root_markers,
  settings = {
    languages = {
      proto = {
        {
          lintSource = 'buf-linter',
          lintCommand = 'buf lint',
          lintFormats = { '%f:%l:%c:%m' },
          lintStdin = false,
          lintWorkSpace = true,
          lintSeverity = 2,
          rootMarkers = vim.iter(root_markers):flatten():totable(),
        }
      }
    }
  }
}
