local lsp = require('utils.lsp')

local root_patterns = {
  'Pipfile',
  'pyproject.toml',
  'requirements.txt',
  'setup.cfg',
  'setup.py',
  'tox.ini',
}

local linter, formatter

local ruff = lsp.start({
  cmd = { 'ruff', 'server' },
  root_patterns = vim.list_extend(
    { 'ruff.toml', '.ruff.toml' },
    root_patterns
  ),
})

-- Prefer ruff over pylint and black as linter and formatter
if ruff then
  linter = ruff
  formatter = ruff
end

linter = linter -- luacheck: ignore 311
  or (function()
    local pylint_root_patterns = vim.list_extend({ 'pylintrc' }, root_patterns)
    return lsp.start({
      cmd = { 'efm-langserver' },
      requires = { 'pylint' },
      name = 'efm-linter-pylint',
      root_patterns = pylint_root_patterns,
      settings = {
        languages = {
          python = {
            {
              lintSource = 'pylint',
              lintCommand = 'pylint --score=no --from-stdin "${INPUT}"',
              lintFormats = { '%f:%l:%c: %t%.%#: %m' },
              lintStdin = true,
              lintSeverity = 2,
              rootMarkers = pylint_root_patterns,
            },
          },
        },
      },
    })
  end)()

linter = linter -- luacheck: ignore 311
  or (function()
    local flake8_root_patterns = vim.list_extend({ '.flake8' }, root_patterns)
    return lsp.start({
      cmd = { 'efm-langserver' },
      requires = { 'flake8' },
      name = 'efm-linter-flake8',
      root_patterns = flake8_root_patterns,
      settings = {
        languages = {
          -- Source: https://github.com/creativenull/efmls-configs-nvim/blob/main/lua/efmls-configs/linters/flake8.lua
          python = {
            {
              lintSource = 'flake8',
              lintCommand = 'flake8 -',
              lintFormats = { 'stdin:%l:%c: %t%n %m' },
              lintIgnoreExitCode = true,
              lintStdin = true,
              rootMarkers = flake8_root_patterns,
            },
          },
        },
      },
    })
  end)()

-- Use efm to attach black formatter as a language server
formatter = formatter
  or lsp.start({
    cmd = { 'efm-langserver' },
    requires = { 'black' },
    root_patterns = root_patterns,
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
local isort_root_patterns = vim.list_extend({ '.isort.cfg' }, root_patterns)
lsp.start({
  cmd = { 'efm-langserver' },
  requires = { 'isort' },
  root_patterns = isort_root_patterns,
  name = 'efm-formatter-isort',
  init_options = { documentFormatting = true },
  settings = {
    languages = {
      python = {
        {
          formatCommand = 'isort --quiet -',
          formatStdin = true,
          rootMarkers = isort_root_patterns,
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

local pyright_root_patterns =
  vim.list_extend({ 'pyrightconfig.json' }, root_patterns)

local pyright_settings = {
  analysis = {
    autoSearchPaths = true,
    useLibraryCodeForTypes = true,
    diagnosticMode = 'openFilesOnly',
  },
}

---@param client vim.lsp.Client
---@param path string
local function pyright_set_python_path(client, path)
  if client.settings then
    client.settings.python = vim.tbl_deep_extend(
      'force',
      client.settings.python,
      { pythonPath = path }
    )
  else
    client.config.settings = vim.tbl_deep_extend(
      'force',
      client.config.settings,
      { python = { pythonPath = path } }
    )
  end
  client.notify('workspace/didChangeConfiguration', { settings = nil })
end

---@param client vim.lsp.Client
---@param name string
local function pyright_organize_imports(client, name)
  client.request('workspace/executeCommand', {
    command = string.format('%s.organizeimports', name),
    arguments = { vim.uri_from_bufnr(0) },
  }, nil, 0)
end

---@param name string
---@return fun(vim.lsp.Client)
local function pyright_on_attach(name)
  return function(client)
    if disable_formatting then
      disable_formatting(client)
    end
    vim.api.nvim_buf_create_user_command(
      0,
      'PyrightOrganizeImports',
      function()
        pyright_organize_imports(client, name)
      end,
      { desc = 'Organize python imports' }
    )
    vim.api.nvim_buf_create_user_command(
      0,
      'PyrightSetPythonPath',
      function(args)
        pyright_set_python_path(client, args.args)
      end,
      {
        desc = string.format(
          'Reconfigure %s with the provided python path',
          name
        ),
        nargs = 1,
        complete = 'file',
      }
    )
  end
end

local server_configs = {
  {
    cmd = { 'basedpyright-langserver', '--stdio' },
    root_patterns = pyright_root_patterns,
    on_attach = pyright_on_attach('basedpyright'),
    settings = {
      basedpyright = pyright_settings,
    },
  },
  {
    cmd = { 'pyright-langserver', '--stdio' },
    root_patterns = pyright_root_patterns,
    on_attach = pyright_on_attach('pyright'),
    settings = {
      python = pyright_settings,
    },
  },
  {
    cmd = { 'pylsp' },
    root_patterns = root_patterns,
    on_attach = disable_formatting,
  },
  {
    cmd = { 'jedi-language-server' },
    root_patterns = root_patterns,
    on_attach = disable_formatting,
  },
}

for _, server_config in ipairs(server_configs) do
  if lsp.start(server_config) then
    return
  end
end
