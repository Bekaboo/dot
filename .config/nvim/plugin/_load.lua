-- Lazy-load builtin plugins

-- vscode-neovim
if vim.g.vscode then
  vim.fn['plugin#vscode#setup']()
  return
end

-- expandtab
vim.api.nvim_create_autocmd('InsertEnter', {
  once = true,
  group = vim.api.nvim_create_augroup('ExpandTabSetup', {}),
  callback = function()
    require('plugin.expandtab').setup()
  end,
})

-- fcitx5
vim.api.nvim_create_autocmd('ModeChanged', {
  once = true,
  pattern = '*:[ictRss\x13]*',
  group = vim.api.nvim_create_augroup('IMSetup', {}),
  callback = function()
    require('plugin.fcitx5').setup()
    return true
  end,
})

-- jupytext
vim.api.nvim_create_autocmd('BufReadCmd', {
  once = true,
  pattern = '*.ipynb',
  group = vim.api.nvim_create_augroup('JupyTextSetup', {}),
  callback = function(info)
    require('plugin.jupytext').setup(info.buf)
    return true
  end,
})

-- lsp & diagnostic settings
vim.api.nvim_create_autocmd({ 'LspAttach', 'DiagnosticChanged' }, {
  once = true,
  desc = 'Apply lsp and diagnostic settings.',
  group = vim.api.nvim_create_augroup('LspDiagnosticSetup', {}),
  callback = function()
    require('plugin.lsp').setup()
    return true
  end,
})

-- readline
vim.api.nvim_create_autocmd({ 'CmdlineEnter', 'InsertEnter' }, {
  group = vim.api.nvim_create_augroup('ReadlineSetup', {}),
  once = true,
  callback = function()
    require('plugin.readline').setup()
    return true
  end,
})

-- colorcolumn
vim.api.nvim_create_autocmd('UIEnter', {
  group = vim.api.nvim_create_augroup('ColorColumnSetup', {}),
  desc = 'Init colorcolumn plugin.',
  once = true,
  callback = function()
    vim.schedule(function()
      require('plugin.colorcolumn').setup()
    end)
    return true
  end,
})

-- winbar
vim.api.nvim_create_autocmd('FileType', {
  once = true,
  group = vim.api.nvim_create_augroup('WinBarSetup', {}),
  callback = function()
    local winbar = require('plugin.winbar')
    local api = require('plugin.winbar.api')
    winbar.setup({ bar = { hover = false } })

    -- stylua: ignore start
    vim.keymap.set('n', '<Leader>;', api.pick, { desc = 'Pick symbols in winbar' })
    vim.keymap.set('n', '[;', api.goto_context_start, { desc = 'Go to start of current context' })
    vim.keymap.set('n', '];', api.select_next_context, { desc = 'Select next context' })
    -- stylua: ignore end
    return true
  end,
})

-- tabline, statusline, statuscolumn
vim.go.tabline = [[%!v:lua.require'plugin.tabline'()]]
vim.go.statusline = [[%!v:lua.require'plugin.statusline'()]]
vim.opt.statuscolumn = [[%!v:lua.require'plugin.statuscolumn'()]]

-- term
vim.api.nvim_create_autocmd('TermOpen', {
  group = vim.api.nvim_create_augroup('TermSetup', {}),
  callback = function(info)
    require('plugin.term').setup(info.buf)
  end,
})

-- tmux
if vim.g.has_ui then
  vim.api.nvim_create_autocmd('UIEnter', {
    group = vim.api.nvim_create_augroup('TmuxSetup', {}),
    desc = 'Init tmux plugin.',
    once = true,
    callback = function()
      vim.schedule(function()
        require('plugin.tmux').setup()
      end)
      return true
    end,
  })
end

-- tabout
vim.api.nvim_create_autocmd({ 'InsertEnter', 'CmdlineEnter' }, {
  group = vim.api.nvim_create_augroup('TabOutSetup', {}),
  desc = 'Init tabout plugin.',
  once = true,
  callback = function()
    require('plugin.tabout').setup()
    return true
  end,
})

-- z
vim.api.nvim_create_autocmd({ 'CmdlineEnter', 'CmdUndefined' }, {
  group = vim.api.nvim_create_augroup('ZSetup', {}),
  desc = 'Init z plugin.',
  once = true,
  callback = function()
    require('plugin.z').setup()
    return true
  end,
})
