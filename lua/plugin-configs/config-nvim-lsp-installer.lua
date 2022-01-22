local get = require('utils/get')
local langs = require('utils/langs')
local ensure_installed = get.lsp_server_list(langs)

-- Config for `nvim-lsp-installer`
require('nvim-lsp-installer').settings({
  ui = {
    icons = {
      server_installed = '',
      server_pending = '',
      server_uninstalled = ''
    }
  }
})

-- Ensure `cmp-nvim-lsp` and and `nvim-lspconfig` are loaded
vim.cmd [[ :packadd cmp-nvim-lsp ]]
vim.cmd [[ :packadd nvim-lspconfig ]]

-------------------------- on_attach function begins ---------------------------
-- Use an on_attach function to only map the following keys
-- after the language server attaches to the current buffer
local on_attach =
  function(client, bufnr)
    local function buf_set_keymap(...) vim.api.nvim_buf_set_keymap(bufnr, ...) end
    local function buf_set_option(...) vim.api.nvim_buf_set_option(bufnr, ...) end

    -- Enable completion triggered by <c-x><c-o>
    buf_set_option('omnifunc', 'v:lua.vim.lsp.omnifunc')

    -- Mappings.
    -- See `:help vim.lsp.*` for documentation on any of the below functions
    local opts = { noremap=true }
    buf_set_keymap('n', '<Leader>lD', '<cmd>lua vim.lsp.buf.declaration()<CR>', opts)
    buf_set_keymap('n', '<Leader>ld', '<cmd>lua vim.lsp.buf.definition()<CR>', opts)
    buf_set_keymap('n', '<Leader>lh', '<cmd>lua vim.lsp.buf.hover()<CR>', opts)
    buf_set_keymap('n', '<Leader>li', '<cmd>lua vim.lsp.buf.implementation()<CR>', opts)
    buf_set_keymap('n', '<Leader>ls', '<cmd>lua vim.lsp.buf.signature_help()<CR>', opts)
    buf_set_keymap('n', '<Leader>lwa', '<cmd>lua vim.lsp.buf.add_workspace_folder()<CR>', opts)
    buf_set_keymap('n', '<Leader>lwd', '<cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>', opts)
    buf_set_keymap('n', '<Leader>lwl', '<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>', opts)
    buf_set_keymap('n', '<Leader>lt', '<cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
    buf_set_keymap('n', '<Leader>lrn', '<cmd>lua vim.lsp.buf.rename()<CR>', opts)
    buf_set_keymap('n', '<Leader>lac', '<cmd>lua vim.lsp.buf.code_action()<CR>', opts)
    buf_set_keymap('n', '<Leader>lrf', '<cmd>lua vim.lsp.buf.references()<CR>', opts)
    buf_set_keymap('n', '<Leader>ldi', '<cmd>lua vim.diagnostic.open_float()<CR>', opts)
    buf_set_keymap('n', '[d', '<cmd>lua vim.diagnostic.goto_prev()<CR>', opts)
    buf_set_keymap('n', ']d', '<cmd>lua vim.diagnostic.goto_next()<CR>', opts)
    buf_set_keymap('n', '<Leader>lls', '<cmd>lua vim.diagnostic.setloclist()<CR>', opts)
    buf_set_keymap('n', '<Leader>lf', '<cmd>lua vim.lsp.buf.formatting()<CR>', opts)
  end
--------------------------- on_attach function ends ----------------------------

-- Add additional capabilities supported by nvim-cmp
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').update_capabilities(capabilities)

-- Automatically install servers in `ensure_installed`
-- and add additional capabilities supported by nvim-cmp
for _, server_name in pairs(ensure_installed) do
  local server_available, requested_server
    = require('nvim-lsp-installer').get_server(server_name)
  if server_available then
    if not requested_server:is_installed() then
      print('[lsp-installer]: installing ' .. server_name)
      requested_server:install()
    end
    requested_server:on_ready(function()
      requested_server:setup {
        on_attach = on_attach,
        capabilities = capabilities,
        settings = get.lsp_server_config(server_name)
      }
    end)
  else
    print('[lsp-installer]: server ' .. server_name .. ' not available')
  end
end
