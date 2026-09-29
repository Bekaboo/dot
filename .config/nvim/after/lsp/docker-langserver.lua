-- A language server for Dockerfiles powered by Node.js, TypeScript, and VSCode
-- technologies
--
-- https://github.com/rcjsuen/dockerfile-language-server

---@type my.lsp.config
return {
  filetypes = { 'dockerfile' },
  cmd = {
    'docker-langserver',
    '--stdio',
  },
  root_markers = { 'Dockerfile' },
}
