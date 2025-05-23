local lsp = require('utils.lsp')

-- Symbol rename, go to references, definitions, etc.
lsp.start({
  cmd = { 'protols' },
  root_markers = { 'protols.toml' },
})

-- Diagnostics
lsp.start({
  cmd = { 'buf', 'beta', 'lsp' },
  name = 'buf-lsp',
})
