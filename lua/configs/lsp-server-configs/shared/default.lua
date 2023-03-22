local function on_attach(client, bufnr)
  -- Enable completion triggered by <c-x><c-o>
  vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

  -- LSP clients should disable themselves' formatting capability
  -- if a null-ls formatter is attached
  if client.name ~= 'null-ls' then
    local null_ls_sources_ok, null_ls_sources =
      pcall(require, 'null-ls.sources')
    if null_ls_sources_ok then
      local null_ls_supports_formatting = not vim.tbl_isempty(
        null_ls_sources.get_available(vim.bo[bufnr].ft, 'NULL_LS_FORMATTING')
      )
      local null_ls_supports_range_formatting = not vim.tbl_isempty(
        null_ls_sources.get_available(
          vim.bo[bufnr].ft,
          'NULL_LS_RANGE_FORMATTING'
        )
      )
      if null_ls_supports_formatting then
        client.server_capabilities.documentFormattingProvider = false
      end
      if null_ls_supports_range_formatting then
        client.server_capabilities.documentRangeFormattingProvider = false
      end
    end
  end

  -- Use an on_attach function to only map the following keys
  vim.keymap.set('n', '<Leader>wa', vim.lsp.buf.add_workspace_folder,                                                      { buffer = bufnr })
  vim.keymap.set('n', '<Leader>wd', vim.lsp.buf.remove_workspace_folder,                                                   { buffer = bufnr })
  vim.keymap.set('n', '<Leader>wl', function() vim.print(vim.lsp.buf.list_workspace_folders()) end,                        { buffer = bufnr })
  vim.keymap.set('n', '<Leader>ca', vim.lsp.buf.code_action,                                                               { buffer = bufnr })
  vim.keymap.set('n', '<Leader>r',  vim.lsp.buf.rename,                                                                    { buffer = bufnr })
  vim.keymap.set('n', '<Leader>R',  vim.lsp.buf.references,                                                                { buffer = bufnr })
  vim.keymap.set('n', '<Leader>e',  vim.diagnostic.open_float,                                                             { buffer = bufnr })
  vim.keymap.set('n', '<leader>E',  vim.diagnostic.setloclist,                                                             { buffer = bufnr })
  vim.keymap.set('n', '[e',         vim.diagnostic.goto_prev,                                                              { buffer = bufnr })
  vim.keymap.set('n', ']e',         vim.diagnostic.goto_next,                                                              { buffer = bufnr })
  vim.keymap.set('n', '[E',         function() vim.diagnostic.goto_prev({ severity = vim.diagnostic.severity.ERROR }) end, { buffer = bufnr })
  vim.keymap.set('n', ']E',         function() vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.ERROR }) end, { buffer = bufnr })
  vim.keymap.set('n', '[W',         function() vim.diagnostic.goto_prev({ severity = vim.diagnostic.severity.WARN }) end,  { buffer = bufnr })
  vim.keymap.set('n', ']W',         function() vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.WARN }) end,  { buffer = bufnr })
  vim.keymap.set('n', 'gd', function()
    if not client.supports_method('textDocument/definition') then
      vim.api.nvim_feedkeys('gd', 'in', false)
      return
    end
    vim.lsp.buf.definition()
  end, { buffer = bufnr })
  vim.keymap.set('n', 'gD', function()
    if not client.supports_method('textDocument/typeDefinition') then
      vim.api.nvim_feedkeys('gD', 'in', false)
      return
    end
    vim.lsp.buf.type_definition()
  end, { buffer = bufnr })
  vim.keymap.set('n', 'K', function()
    if not client.supports_method('textDocument/hover') then
      vim.api.nvim_feedkeys('K', 'in', false)
      return
    end
    vim.lsp.buf.hover()
  end, { buffer = bufnr })

  -- Format on save
  vim.b.lsp_format_on_save = vim.g.lsp_format_on_save
  vim.api.nvim_buf_create_user_command(
    bufnr,
    'LspFormat',
    function(tbl)
      if vim.tbl_contains(tbl.fargs, '?') then
        vim.notify(
          '[LSP] format-on-save: turned '
            .. (vim.b.lsp_format_on_save and 'on' or 'off')
            .. ' locally, '
            .. (vim.g.lsp_format_on_save and 'enabled' or 'disabled')
            .. ' globally',
          vim.log.levels.INFO
        )
        return
      end

      local global = not vim.tbl_contains(tbl.fargs, '--local')

      if vim.tbl_contains(tbl.fargs, 'on') then
        vim.b.lsp_format_on_save = true
        if global then
          vim.g.lsp_format_on_save = true
        end
      elseif vim.tbl_contains(tbl.fargs, 'off') then
        vim.b.lsp_format_on_save = false
        if global then
          vim.g.lsp_format_on_save = false
        end
      else -- toggle
        vim.b.lsp_format_on_save = not vim.b.lsp_format_on_save
        vim.g.lsp_format_on_save = vim.b.lsp_format_on_save
      end

      vim.notify(
        '[LSP] format-on-save: '
          .. (vim.b.lsp_format_on_save and 'on' or 'off'),
        vim.log.levels.INFO
      )
    end,
    {
      nargs = '*',
      complete = function(arg_before, _, _)
        local completion = {
          [''] = {
            'on',
            'off',
            'toggle',
            '--local',
          },
          ['--'] = {
            'local',
          },
        }
        return completion[arg_before] or {}
      end,
      desc = 'Set LSP format-on-save functionality.',
    }
  )
  vim.api.nvim_create_augroup('LspFormat', { clear = false })
  vim.api.nvim_create_autocmd('BufWritePre', {
    buffer = bufnr,
    group = 'LspFormat',
    callback = function()
      if vim.b.lsp_format_on_save then
        vim.lsp.buf.format({
          bufnr = bufnr,
          timeout_ms = 500,
        })
      end
    end,
  })
end

local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities.offsetEncoding = 'utf-8'
local cmp_nvim_lsp_ok, cmp_nvim_lsp = pcall(require, 'cmp_nvim_lsp')
if cmp_nvim_lsp_ok then
  capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
end

local default_config = {
  on_attach = on_attach,
  capabilities = capabilities,
}

return default_config
