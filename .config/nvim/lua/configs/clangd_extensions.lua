local icons = require('utils.static').icons

require('clangd_extensions').setup({
  ast = {
    role_icons = {
      ['type'] = icons.Type,
      ['declaration'] = icons.Function,
      ['expression'] = icons.Snippet,
      ['specifier'] = icons.Specifier,
      ['statement'] = icons.Statement,
      ['template argument'] = icons.TypeParameter,
    },
    kind_icons = {
      ['Compound'] = icons.Namespace,
      ['Recovery'] = icons.DiagnosticSignError,
      ['TranslationUnit'] = icons.Unit,
      ['PackExpansion'] = icons.Ellipsis,
      ['TemplateTypeParm'] = icons.TypeParameter,
      ['TemplateTemplateParm'] = icons.TypeParameter,
      ['TemplateParamObject'] = icons.TypeParameter,
    },
  },
  memory_usage = { border = 'solid' },
  symbol_info = { border = 'solid' },
})

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Set clangd keymaps.',
  group = vim.api.nvim_create_augroup('ClangdSetKeymaps', {}),
  pattern = { 'c', 'cpp', 'objc', 'objcpp', 'cuda' },
  callback = function(info)
    vim.keymap.set(
      'n',
      '<Leader>6',
      require('clangd_extensions.switch_source_header').switch_source_header,
      {
        buffer = info.buf,
        desc = 'Switch between source and header',
      }
    )
  end,
})

-- Insert comparator in nvim-cmp's comparators list
local cmp_ok, cmp = pcall(require, 'cmp')
if cmp_ok then
  cmp.setup.filetype({ 'c', 'cpp' }, {
    sorting = {
      comparators = vim.list_extend({
        require('clangd_extensions.cmp_scores'),
      }, require('cmp.config').get().sorting.comparators),
    },
  })
end
