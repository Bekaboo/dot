-- Scala language server with rich IDE features
-- https://scalameta.org/metals/

---@type lsp.config
return {
  filetypes = { 'scala' },
  cmd = { 'metals' },
  root_markers = {
    'build.sbt',
    'build.sc',
    'build.gradle',
    'pom.xml',
  },
  init_options = {
    statusBarProvider = 'show-message',
    isHttpEnabled = true,
    compilerOptions = {
      snippetAutoIndent = false,
    },
  },
  capabilities = {
    workspace = {
      configuration = false,
    },
  },
}
