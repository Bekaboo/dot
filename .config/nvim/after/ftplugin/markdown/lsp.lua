local lsp = require('utils.lsp')

local server_configs = {
  {
    cmd = { 'marksman' },
    root_markers = { '.marksman.toml' },
  },
  {
    cmd = { 'markdown-oxide' },
    root_markers = { '.moxide.toml' },
  },
}

for _, server_config in ipairs(server_configs) do
  if lsp.start(server_config) then
    return
  end
end
