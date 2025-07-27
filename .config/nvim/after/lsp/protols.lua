---@type lsp_config_t
return {
  filetypes = { 'proto' },
  cmd = { 'protols' },
  root_markers = { 'protols.toml' },
  handlers = {
    -- Disable diagnostics from protols as it has too many false alarms
    -- Method to disable diagnostics comes from https://www.reddit.com/r/neovim/comments/13qurat/how_to_disable_diagnostics_for_specific_lsp_server
    [vim.lsp.protocol.Methods.textDocument_publishDiagnostics] = function() end,
  },
}
