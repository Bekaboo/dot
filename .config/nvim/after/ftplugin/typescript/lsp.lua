-- Shared lsp config for front end dev:
-- - javascript
-- - typescript
-- - json
-- - jsonc
-- - html
-- - css

vim.lsp.enable('typescript-language-server')
vim.lsp.enable('eslint')
vim.lsp.enable('prettier')
vim.lsp.enable('biome') -- prefer biome over prettier as formatter
