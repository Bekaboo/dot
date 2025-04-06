local lsp = require('utils.lsp')

local root_markers = {
  'Pipfile',
  'pyproject.toml',
  'requirements.txt',
  'setup.cfg',
  'setup.py',
  'tox.ini',
}

local formatter = lsp.start({
  cmd = { 'ruff', 'server' },
  buf_support = false,
  root_markers = vim.list_extend({ 'ruff.toml', '.ruff.toml' }, root_markers),
})

local pylint_root_markers = vim.list_extend({ 'pylintrc' }, root_markers)
lsp.start({
  cmd = { 'efm-langserver' },
  requires = { 'pylint' },
  name = 'efm-linter-pylint',
  root_markers = pylint_root_markers,
  settings = {
    languages = {
      python = {
        {
          lintSource = 'pylint',
          lintCommand = 'pylint --disable line-too-long,import-error --score=no --from-stdin "${INPUT}"',
          lintFormats = { '%f:%l:%c: %t%.%#: %m' },
          lintStdin = true,
          lintSeverity = 2,
          rootMarkers = pylint_root_markers,
        },
      },
    },
  },
})

local flake8_root_markers = vim.list_extend({ '.flake8' }, root_markers)
lsp.start({
  cmd = { 'efm-langserver' },
  requires = { 'flake8' },
  name = 'efm-linter-flake8',
  root_markers = flake8_root_markers,
  settings = {
    languages = {
      -- Source: https://github.com/creativenull/efmls-configs-nvim/blob/main/lua/efmls-configs/linters/flake8.lua
      python = {
        {
          lintSource = 'flake8',
          lintCommand = 'flake8 --ignore=E501 -', -- ignore line length error
          lintFormats = { 'stdin:%l:%c: %t%n %m' },
          lintIgnoreExitCode = true,
          lintStdin = true,
          rootMarkers = flake8_root_markers,
        },
      },
    },
  },
})

local mypy_root_markers =
  vim.list_extend({ 'mypy.ini', '.mypy.ini' }, root_markers)
lsp.start({
  cmd = { 'efm-langserver' },
  requires = { 'mypy' },
  name = 'efm-linter-mypy',
  root_markers = mypy_root_markers,
  settings = {
    languages = {
      -- https://github.com/creativenull/efmls-configs-nvim/blob/main/lua/efmls-configs/linters/mypy.lua
      python = {
        {
          lintSource = 'mypy',
          lintCommand = 'mypy --disable-error-code import-untyped --show-column-numbers',
          lintFormats = {
            '%f:%l:%c: %trror: %m',
            '%f:%l:%c: %tarning: %m',
            '%f:%l:%c: %tote: %m',
          },
          -- Mypy does not support reading from stdin, see
          -- https://github.com/python/mypy/issues/12235
          lintStdin = false,
          rootMarkers = mypy_root_markers,
        },
      },
    },
  },
})

-- Use efm to attach black formatter as a language server
formatter = formatter
  or lsp.start({
    cmd = { 'efm-langserver' },
    requires = { 'black' },
    root_markers = root_markers,
    name = 'efm-formatter-black',
    init_options = { documentFormatting = true },
    settings = {
      languages = {
        python = {
          {
            formatCommand = 'black --no-color -q -',
            formatStdin = true,
          },
        },
      },
    },
  })

-- Neither black or ruff(*) sort imports on format, so...
-- * Technically ruff can sort imports using the code action
-- `source.organizeImports.ruff` but it is not considered as a format operation
-- and will not run on `vim.lsp.buf.format()`, see
-- https://github.com/astral-sh/ruff/issues/8926#issuecomment-1834048218
local isort_root_markers = vim.list_extend({ '.isort.cfg' }, root_markers)
lsp.start({
  cmd = { 'efm-langserver' },
  requires = { 'isort' },
  root_markers = isort_root_markers,
  name = 'efm-formatter-isort',
  init_options = { documentFormatting = true },
  settings = {
    languages = {
      python = {
        {
          formatCommand = 'isort --quiet -',
          formatStdin = true,
          rootMarkers = isort_root_markers,
        },
      },
    },
  },
})

---Disable lsp formatting capabilities if efm launched successfully
---@type fun(client: vim.lsp.Client, bufnr: integer)?
local disable_formatting
if formatter then
  function disable_formatting(client)
    client.server_capabilities.documentFormattingProvider = false
  end
end

local pyright_root_markers =
  vim.list_extend({ 'pyrightconfig.json' }, root_markers)

local pyright_settings = {
  -- Too many warnings in default 'recommended' mode from basedpyright
  typeCheckingMode = 'standard',
  analysis = {
    autoSearchPaths = true,
    useLibraryCodeForTypes = true,
    diagnosticMode = 'openFilesOnly',
  },
}

local server_configs = {
  {
    cmd = { 'basedpyright-langserver', '--stdio' },
    root_markers = pyright_root_markers,
    settings = {
      basedpyright = pyright_settings,
    },
    on_attach = disable_formatting,
  },
  {
    cmd = { 'pyright-langserver', '--stdio' },
    root_markers = pyright_root_markers,
    settings = {
      python = pyright_settings,
    },
    on_attach = disable_formatting,
  },
  {
    cmd = { 'pylsp' },
    root_markers = root_markers,
    on_attach = disable_formatting,
  },
  {
    cmd = { 'jedi-language-server' },
    root_markers = root_markers,
    on_attach = disable_formatting,
  },
}

for _, server_config in ipairs(server_configs) do
  if lsp.start(server_config) then
    return
  end
end
