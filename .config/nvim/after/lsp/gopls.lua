-- Suppress error 'SWIG + Go: C source files not allowed when not using cgo'
-- https://stackoverflow.com/questions/30248259/swig-go-c-source-files-not-allowed-when-not-using-cgo
vim.env.CGO_ENABLED = 0

---@type lsp.config
return {
  filetypes = { 'go' },
  cmd = { 'gopls' },
  root_markers = { 'go.work', 'go.mod' },
  settings = {
    gopls = {
      completeUnimported = true,
      usePlaceholders = true,
      analyses = {
        unusedparams = true,
        shadow = true,
      },
      staticcheck = true,
      hints = {
        assignVariableTypes = true,
        compositeLiteralFields = true,
        constantValues = true,
        functionTypeParameters = true,
        parameterNames = true,
        rangeVariableTypes = true,
      },
    },
  },
}
