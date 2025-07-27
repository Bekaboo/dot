---@type lsp_config_t
return {
  filetypes = { 'vim' },
  cmd = { 'vim-language-server', '--stdio' },
  init_options = {
    isNeovim = true,
    iskeyword = vim.bo.iskeyword,
    vimruntime = '',
    runtimepath = '',
    diagnostic = { enable = true },
    indexes = {
      count = 4,
      gap = 100,
      runtimepath = true,
      projectRootPatterns = {
        '.git/',
        'nvim/',
        'plugin/',
        'runtime/',
        'autoload/',
      },
    },
    suggest = {
      fromVimruntime = true,
      fromRuntimepath = true,
    },
  },
}
