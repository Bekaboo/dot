-- LSP config file for javascript, typescript, json, jsonc, html, and css

local lsp = require('utils.lsp')
local formatter

-- Prefer biome over prettier as formatter
-- Biome currently only supports json, jsonc, javascript, and typescript
if
  vim.bo.ft == 'json'
  or vim.bo.ft == 'jsonc'
  or vim.bo.ft == 'javascript'
  or vim.bo.ft == 'typescript'
then
  formatter = lsp.start({
    cmd = { 'biome', 'lsp-proxy' },
    root_patterns = {
      'biome.json',
      'biome.jsonc',
    },
  })
end

if not formatter then
  local prettier_cmd = vim.fn.executable('prettier_d') == 1 and 'prettier_d'
    or vim.fn.executable('prettierd') == 1 and 'prettierd'
    or vim.fn.executable('prettier') == 1 and 'prettier'

  if prettier_cmd then
    local prettier_root_patterns = {
      'prettier.config.js',
      'prettier.config.mjs',
      'prettier.config.cjs',
      '.prettierrc',
      '.prettierrc.js',
      '.prettierrc.mjs',
      '.prettierrc.cjs',
      '.prettierrc.json',
      '.prettierrc.hjson',
      '.prettierrc.json5',
      '.prettierrc.toml',
      '.prettierrc.yaml',
      '.prettierrc.yml',
      'package.json',
    }

    local prettier_lang_settings = {
      {
        formatCommand = prettier_cmd
          .. ' --stdin-filepath ${INPUT} ${--range-start=charStart} ${--range-end=charEnd} ${--tab-width=tabWidth} ${--use-tabs=!insertSpaces}',
        formatCanRange = true,
        formatStdin = true,
        rootMarkers = prettier_root_patterns,
      },
    }

    formatter = lsp.start({
      cmd = { 'efm-langserver' },
      name = 'efm-formatter-' .. prettier_cmd,
      root_patterns = prettier_root_patterns,
      init_options = {
        documentFormatting = true,
        documentRangeFormatting = true,
      },
      settings = {
        languages = {
          -- Setup all supported languages because this lsp config file
          -- is shared between all these filetypes
          javascript = prettier_lang_settings,
          typescript = prettier_lang_settings,
          jsonc = prettier_lang_settings,
          json = prettier_lang_settings,
          html = prettier_lang_settings,
          css = prettier_lang_settings,
        },
      },
    })
  end
end

---@param client vim.lsp.Client
local function disable_formatting(client)
  client.server_capabilities.documentFormattingProvider = false
  client.server_capabilities.documentRangeFormattingProvider = false
end

local eslint_cmd = vim.fn.executable('eslint-language-server') == 1
    and 'eslint-language-server'
  or vim.fn.executable('vscode-eslint-language-server') == 1 and 'vscode-eslint-language-server'
  or vim.fn.executable('eslint_d') == 1 and 'eslint_d'
  or vim.fn.executable('eslintd') == 1 and 'eslintd'
  or vim.fn.executable('eslint') == 1 and 'eslint'

if eslint_cmd then
  local eslint_client_id
  local eslint_root_patterns = {
    'eslint.config.js',
    'eslint.config.mjs',
    'eslint.config.cjs',
    '.eslintrc.js',
    '.eslintrc.cjs',
    '.eslintrc.yml',
    '.eslintrc.yaml',
    '.eslintrc.json',
  }

  if vim.endswith(eslint_cmd, 'eslint-language-server') then
    -- Source: https://github.com/neovim/nvim-lspconfig/blob/master/lua/lspconfig/configs/eslint.lua
    eslint_client_id = lsp.start({
      cmd = { eslint_cmd, '--stdio' },
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
        ['eslint/probeFailed'] = function()
          vim.notify(string.format('[%s] ESLint probe failed', eslint_cmd))
          return {}
        end,
        ['eslint/noLibrary'] = function()
          vim.notify(
            string.format('[%s] Unable to find ESLint library', eslint_cmd)
          )
          return {}
        end,
      },
      on_attach = function(client)
        if formatter then
          disable_formatting(client)
        end
        vim.api.nvim_buf_create_user_command(0, 'EslintFixAll', function(args)
          local buf = vim.api.nvim_get_current_buf()
          local request = require('utils.cmd').parse_cmdline_args(args.fargs).async
              and function(bufnr, method, params)
                client.request(method, params, nil, bufnr)
              end
            or function(bufnr, method, params)
              client.request_sync(method, params, nil, bufnr)
            end

          request(0, 'workspace/executeCommand', {
            command = 'eslint.applyAllFixes',
            arguments = {
              {
                uri = vim.uri_from_bufnr(buf),
                version = vim.lsp.util.buf_versions[buf],
              },
            },
          })
        end, {
          desc = 'Fix all eslint problems for this buffer',
          nargs = '?',
          complete = require('utils.cmd').complete(nil, { 'async' }),
        })
      end,
      before_init = function(_, config)
        local root_dir = config.root_dir
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
        if vim.iter(eslint_root_patterns):any(file_exists) then
          config.settings.experimental.useFlatConfig = true
        end

        -- Support Yarn2 (PnP) projects
        if vim.iter({ '.pnp.cjs', '.pnp.js' }):any(file_exists) then
          config.cmd = vim.list_extend({ 'yarn', 'exec' }, config.cmd)
        end
      end,
    })
  else
    local eslint_lang_settings = {
      {
        formatCommand = eslint_cmd == 'eslint' and 'eslint --fix ${INPUT}'
          or eslint_cmd
            .. ' --fix-to-stdout --stdin --stdin-filename ${INPUT}',
        formatStdin = true,
        lintCommand = eslint_cmd
          .. ' --no-color --format visualstudio --stdin --stdin-filename ${INPUT}',
        lintFormats = {
          '%f(%l,%c): %trror : %m',
          '%f(%l,%c): %tarning : %m',
        },
        lintSource = eslint_cmd,
        lintStdin = true,
        lintIgnoreExitCode = true,
        rootMarkers = eslint_root_patterns,
      },
    }

    eslint_client_id = lsp.start({
      cmd = { 'efm-langserver' },
      name = string.format(
        'efm-linter%s-%s',
        formatter and '' or '&formatter',
        eslint_cmd
      ),
      init_options = {
        documentFormatting = true,
        documentRangeFormatting = true,
      },
      on_attach = formatter and disable_formatting,
      root_patterns = eslint_root_patterns,
      settings = {
        languages = {
          javascript = eslint_lang_settings,
          typescript = eslint_lang_settings,
          jsonc = eslint_lang_settings,
          json = eslint_lang_settings,
          html = eslint_lang_settings,
          css = eslint_lang_settings,
        },
      },
    })
  end

  formatter = formatter or eslint_client_id
end

if vim.bo.ft == 'typescript' or vim.bo.ft == 'javascript' then
  lsp.start({
    cmd = { 'typescript-language-server', '--stdio' },
    root_patterns = {
      'tsconfig.json',
      'jsconfig.json',
      'package.json',
    },
    init_options = { hostInfo = 'neovim' },
    on_attach = formatter and disable_formatting,
  })
end
