local cmd = 'eslint'

local cmds = {
  'eslint-language-server',
  'vscode-eslint-language-server',
  'eslint_d',
  'eslintd',
  'eslint',
}

for _, c in ipairs(cmds) do
  if vim.fn.executable(c) == 1 then
    cmd = c
    break
  end
end

local fts = {
  'typescript',
  'javascript',
  'typescriptreact',
  'javascriptreact',
  'json',
  'jsonc',
  'html',
  'css',
}

local root_markers = {
  'eslint.config.js',
  'eslint.config.mjs',
  'eslint.config.cjs',
  '.eslintrc.js',
  '.eslintrc.cjs',
  '.eslintrc.yml',
  '.eslintrc.yaml',
  '.eslintrc.json',
}

-- Prefer eslint native language server over efm + eslint
-- https://github.com/neovim/nvim-lspconfig/blob/master/lua/lspconfig/configs/eslint.lua
if vim.endswith(cmd, 'language-server') then
  return {
    filetypes = fts,
    cmd = { cmd, '--stdio' },
    settings = {
      validate = 'on',
      packageManager = nil,
      useESLintClass = false,
      experimental = { useFlatConfig = false },
      codeActionOnSave = { enable = false, mode = 'all' },
      format = true,
      quiet = false,
      onIgnoredFiles = 'off',
      rulesCustomizations = {},
      run = 'onType',
      problems = { shortenToSingleLine = false },
      -- `nodePath` configures the directory in which the eslint server should start its node_modules resolution.
      -- This path is relative to the workspace folder (root dir) of the server instance.
      nodePath = '',
      -- Use the workspace folder location or the file location (if no workspace folder is open) as the working directory
      workingDirectory = { mode = 'location' },
      codeAction = {
        disableRuleComment = {
          enable = true,
          location = 'separateLine',
        },
      },
    },
    handlers = {
      ['eslint/openDoc'] = function(_, result)
        if not result then
          return
        end
        local sysname = vim.loop.os_uname().sysname
        if sysname:match('Windows') then
          os.execute(string.format('start %q', result.url))
          return
        end
        if sysname:match('Linux') then
          os.execute(string.format('xdg-open %q', result.url))
          return
        end
        os.execute(string.format('open %q', result.url))
        return {}
      end,
      ['eslint/confirmESLintExecution'] = function(_, result)
        if not result then
          return
        end
        return 4 -- approved
      end,
    },
    before_init = function(_, config)
      local root_dir = config.root_dir or vim.fn.getcwd(0)
      -- The 'workspaceFolder' is a VSCode concept, it limits how far the
      -- server will traverse the file system when locating the ESLint config
      -- file (e.g. `.eslintrc`)
      config.settings.workspaceFolder = {
        uri = root_dir,
        name = vim.fn.fnamemodify(root_dir, ':t'),
      }

      ---Check if a file exists in project
      ---@param fpath string
      local function file_exists(fpath)
        return vim.fn.filereadable(vim.fs.joinpath(root_dir, fpath)) == 1
      end

      -- Support flat config
      if vim.iter(root_markers):any(file_exists) then
        config.settings.experimental.useFlatConfig = true
      end

      -- Support Yarn2 (PnP) projects
      if vim.iter({ '.pnp.cjs', '.pnp.js' }):any(file_exists) then
        config.cmd = vim.list_extend({ 'yarn', 'exec' }, config.cmd)
      end
    end,
  }
end

-- Eslint language server not available, fall back to efm + eslint
local eslint_lang_settings = {
  {
    formatCommand = cmd == 'eslint' and 'eslint --fix ${INPUT}'
      or cmd .. ' --fix-to-stdout --stdin --stdin-filename ${INPUT}',
    formatStdin = true,
    lintCommand = cmd
      .. ' --no-color --format visualstudio --stdin --stdin-filename ${INPUT}',
    lintFormats = {
      '%f(%l,%c): %trror : %m',
      '%f(%l,%c): %tarning : %m',
    },
    lintSource = cmd,
    lintAfterOpen = true,
    lintStdin = true,
    lintIgnoreExitCode = true,
  },
}

return {
  filetypes = fts,
  cmd = { 'efm-langserver' },
  requires = { cmd },
  name = cmd,
  init_options = {
    documentFormatting = true,
    documentRangeFormatting = true,
  },
  root_markers = root_markers,
  settings = {
    languages = {
      typescriptreact = eslint_lang_settings,
      javascriptreact = eslint_lang_settings,
      typescript = eslint_lang_settings,
      javascript = eslint_lang_settings,
      jsonc = eslint_lang_settings,
      json = eslint_lang_settings,
      html = eslint_lang_settings,
      css = eslint_lang_settings,
    },
  },
}
