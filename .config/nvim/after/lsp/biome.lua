---@type lsp.config
return {
  filetypes = {
    'json',
    'jsonc',
    'javascript',
    'typescript',
  },
  cmd = {
    'biome',
    'lsp-proxy',
  },
  root_markers = {
    'biome.json',
    'biome.jsonc',
  },
}
