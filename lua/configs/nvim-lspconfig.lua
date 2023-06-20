local static = require('utils.static')
local server_configs = require('configs.lsp-server-configs')

---Customize LSP floating window border
local function lspconfig_floating_win()
  local opts_override = {}

  ---Set LSP floating window options
  local function set_win_opts()
    opts_override = {
      border = 'solid',
      max_width = math.ceil(vim.go.columns * 0.75),
      max_height = math.ceil(vim.go.lines * 0.4),
    }
  end
  set_win_opts()

  -- Reset LSP floating window options on VimResized
  vim.api.nvim_create_augroup('LspFloatingWinOpts', { clear = true })
  vim.api.nvim_create_autocmd('VimResized', {
    group = 'LspFloatingWinOpts',
    callback = set_win_opts,
  })

  -- Hijack LSP floating window function to use custom options
  local _open_floating_preview = vim.lsp.util.open_floating_preview
  ---@diagnostic disable-next-line: duplicate-set-field
  function vim.lsp.util.open_floating_preview(contents, syntax, opts, ...)
    opts = vim.tbl_deep_extend('force', opts, opts_override)
    return _open_floating_preview(contents, syntax, opts, ...)
  end
end

---Customize LSP diagnostic UI
local function lspconfig_diagnostic()
  local icons = static.icons
  for _, severity in ipairs({ 'Error', 'Warn', 'Info', 'Hint' }) do
    local sign_name = 'DiagnosticSign' .. severity
    vim.fn.sign_define(sign_name, {
      text = icons[sign_name],
      texthl = sign_name,
      numhl = sign_name,
    })
  end

  vim.lsp.handlers['textDocument/publishDiagnostics'] =
    vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
      -- Enable underline, use default values
      underline = true,
      -- Enable virtual text, override spacing to 4
      virtual_text = {
        spacing = 4,
        prefix = vim.trim(static.icons.AngleLeft),
      },
    })

  -- Disable LSP diagnostics in diff mode
  vim.api.nvim_create_autocmd('OptionSet', {
    pattern = 'diff',
    group = vim.api.nvim_create_augroup('DiagnosticDisableInDiff', {}),
    callback = function(info)
      if vim.v.option_new == '1' then
        vim.diagnostic.disable(info.buf)
        vim.b._lsp_diagnostics_temp_disabled = true
      elseif
        vim.fn.match(vim.fn.mode(), '[iRsS\x13].*') == -1
        and vim.b._lsp_diagnostics_temp_disabled
      then
        vim.diagnostic.enable(info.buf)
        vim.b._lsp_diagnostics_temp_disabled = nil
      end
    end,
    desc = 'Disable LSP diagnostics in diff mode.',
  })
end

---Customize LspInfo floating window
local function lspconfig_info_win()
  -- setup LspInfo floating window border
  require('lspconfig.ui.windows').default_options.border = 'solid'
  -- reload LspInfo floating window on VimResized
  vim.api.nvim_create_augroup('LspInfoResize', { clear = true })
  vim.api.nvim_create_autocmd('VimResized', {
    pattern = '*',
    group = 'LspInfoResize',
    callback = function()
      if vim.bo.ft == 'lspinfo' then
        vim.api.nvim_win_close(0, true)
        vim.cmd('LspInfo')
      end
    end,
  })
end

local function lspconfig_goto_handers()
  local handlers = {
    ['textDocument/references'] = vim.lsp.handlers['textDocument/references'],
    ['textDocument/definition'] = vim.lsp.handlers['textDocument/definition'],
    ['textDocument/declaration'] = vim.lsp.handlers['textDocument/declaration'],
    ['textDocument/implementation'] = vim.lsp.handlers['textDocument/implementation'],
    ['textDocument/typeDefinition'] = vim.lsp.handlers['textDocument/typeDefinition'],
  }
  for method, handler in pairs(handlers) do
    vim.lsp.handlers[method] = function(err, result, ctx, cfg)
      if not result or type(result) == 'table' and vim.tbl_isempty(result) then
        vim.notify(
          '[LSP] no ' .. method:match('/(%w*)$') .. ' found',
          vim.log.levels.WARN
        )
      end
      handler(err, result, ctx, cfg)
    end
  end
end

---Setup all LSP servers
local function lsp_setup()
  local lspconfig = require('lspconfig')
  local ft_list = vim.tbl_map(function(_)
    return true
  end, static.langs)
  ---@param ft string file type
  ---@return boolean? is_setup
  local function setup_ft(ft)
    if ft_list[ft] then
      ft_list[ft] = nil
      local server_name = static.langs[ft].lsp_server
      if server_name then
        lspconfig[server_name].setup(server_configs[server_name])
        return true
      end
    end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    setup_ft(vim.bo[buf].ft)
  end
  local groupid = vim.api.nvim_create_augroup('LspServerLazySetup', {})
  for ft, _ in pairs(ft_list) do
    vim.api.nvim_create_autocmd('FileType', {
      once = true,
      pattern = ft,
      group = groupid,
      callback = function(info)
        if setup_ft(ft) then
          local bufname = vim.api.nvim_buf_get_name(info.buf)
          if bufname ~= '' and vim.bo[info.buf].bt == '' then
            vim.cmd.edit(bufname)
          end
        end
      end,
    })
  end
end

lspconfig_floating_win()
lspconfig_diagnostic()
lspconfig_info_win()
lspconfig_goto_handers()
lsp_setup()
