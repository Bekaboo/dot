vim.lsp.enable('jedi')
vim.lsp.enable('pylsp')
vim.lsp.enable('pyright')

vim.lsp.enable('flake8')
vim.lsp.enable('pylint')
vim.lsp.enable('mypy')
vim.lsp.enable('pyre')
vim.lsp.enable('pyrefly')

vim.lsp.enable('ruff')
vim.lsp.enable('black')

-- Neither black or ruff(*) sort imports on format, so...
-- * Technically ruff can sort imports using the code action
-- `source.organizeImports.ruff` but it is not considered as a format operation
-- and will not run on `vim.lsp.buf.format()`, see
-- https://github.com/astral-sh/ruff/issues/8926#issuecomment-1834048218
vim.lsp.enable('isort')
