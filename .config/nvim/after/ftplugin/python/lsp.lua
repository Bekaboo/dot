local lsp = require('utils.lsp')

local root_patterns = {
  'Pipfile',
  'pyproject.toml',
  'requirements.txt',
  'setup.cfg',
  'setup.py',
}

lsp.start({
  cmd = { 'efm-langserver' },
  requires = { 'pylint' },
  name = 'efm-linter-pylint',
  root_patterns = root_patterns,
  settings = {
    languages = {
      python = {
        {
          lintSource = 'pylint',
          lintCommand = 'pylint --score=no "${INPUT}"',
          lintFormats = { '%f:%l:%c: %t%.%#: %m' },
          lintStdin = false,
          lintSeverity = 2,
          rootMarkers = root_patterns,
        },
      },
    },
  },
})

-- Use efm to attach black formatter as a language server
local formatter = lsp.start({
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

---Disable lsp formatting capabilities if efm launched successfully
---@type fun(client: vim.lsp.Client, bufnr: integer)?
local disable_formatting
if formatter then
  function disable_formatting(client)
    client.server_capabilities.documentFormattingProvider = false
  end
end

local server_configs = {
  {
    cmd = { 'pyright-langserver', '--stdio' },
    root_patterns = vim.list_extend({ 'pyrightconfig.json' }, root_patterns),
    on_attach = function(client)
      if disable_formatting then
        disable_formatting(client)
      end
      vim.api.nvim_buf_create_user_command(
        0,
        'PyrightOrganizeImports',
        function()
          client.request('workspace/executeCommand', {
            command = 'pyright.organizeimports',
            arguments = { vim.uri_from_bufnr(0) },
          }, nil, 0)
        end,
        { desc = 'Organize python imports' }
      )
      vim.api.nvim_buf_create_user_command(
        0,
        'PyrightSetPythonPath',
        function(args)
          if client.settings then
            client.settings.python = vim.tbl_deep_extend(
              'force',
              client.settings.python,
              { pythonPath = args.args }
            )
          else
            client.config.settings = vim.tbl_deep_extend(
              'force',
              client.config.settings,
              { python = { pythonPath = args.args } }
            )
          end
          client.notify('workspace/didChangeConfiguration', { settings = nil })
        end,
        {
          desc = 'Reconfigure pyright with the provided python path',
          nargs = 1,
          complete = 'file',
        }
      )
    end,
    settings = {
      python = {
        analysis = {
          autoSearchPaths = true,
          useLibraryCodeForTypes = true,
          diagnosticMode = 'openFilesOnly',
        },
      },
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
