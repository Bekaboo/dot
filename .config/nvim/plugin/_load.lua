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

-- jupytext
vim.api.nvim_create_autocmd('BufReadCmd', {
  once = true,
  pattern = '*.ipynb',
  group = vim.api.nvim_create_augroup('JupyTextSetup', {}),
  callback = function(args)
    require('plugin.jupytext').setup(args.buf)
  end,
})

-- lsp & diagnostic commands
vim.api.nvim_create_autocmd({
  'Syntax',
  'FileType',
  'LspAttach',
  'DiagnosticChanged',
}, {
  once = true,
  desc = 'Apply lsp and diagnostic settings.',
  group = vim.api.nvim_create_augroup('LspDiagnosticSetup', {}),
  callback = function()
    require('plugin.lsp-commands').setup()
  end,
})

-- readline
vim.api.nvim_create_autocmd({ 'CmdlineEnter', 'InsertEnter' }, {
  group = vim.api.nvim_create_augroup('ReadlineSetup', {}),
  once = true,
  callback = function()
    require('plugin.readline').setup()
  end,
})

-- winbar
vim.api.nvim_create_autocmd('FileType', {
  once = true,
  group = vim.api.nvim_create_augroup('WinBarSetup', {}),
  callback = function()
    if vim.g.loaded_winbar ~= nil then
      return
    end

    local winbar = require('plugin.winbar')
    local api = require('plugin.winbar.api')
    winbar.setup({ bar = { hover = false } })

    -- stylua: ignore start
    vim.keymap.set('n', '<Leader>;', api.pick, { desc = 'Pick symbols in winbar' })
    vim.keymap.set('n', '[;', api.goto_context_start, { desc = 'Go to start of current context' })
    vim.keymap.set('n', '];', api.select_next_context, { desc = 'Select next context' })
    -- stylua: ignore end
  end,
})

---Load ui elements e.g. tabline, statusline, statuscolumn
---@param name string
local function load_ui(name)
  local loaded_flag = 'loaded_' .. name
  if vim.g[loaded_flag] ~= nil then
    return
  end
  vim.g[loaded_flag] = true
  vim.opt[name] = string.format("%%!v:lua.require'plugin.%s'()", name)
end

load_ui('tabline')
load_ui('statusline')
load_ui('statuscolumn')

-- term
vim.api.nvim_create_autocmd('TermOpen', {
  group = vim.api.nvim_create_augroup('TermSetup', {}),
  callback = function(args)
    local term = require('plugin.term')
    term.setup()
    vim.keymap.set('n', '.', term.rerun, {
      buffer = args.buf,
      desc = 'Re-run terminal job',
    })
  end,
})

-- tmux
if vim.g.has_ui then
  vim.api.nvim_create_autocmd('UIEnter', {
    group = vim.api.nvim_create_augroup('TmuxSetup', {}),
    desc = 'Init tmux plugin.',
    once = true,
    callback = vim.schedule_wrap(function()
      require('plugin.tmux').setup()
    end),
  })
end

-- tabout
vim.api.nvim_create_autocmd({ 'InsertEnter', 'CmdlineEnter' }, {
  group = vim.api.nvim_create_augroup('TabOutSetup', {}),
  desc = 'Init tabout plugin.',
  once = true,
  callback = function()
    require('plugin.tabout').setup()
  end,
})

-- z
do
  local opts = {
    group = vim.api.nvim_create_augroup('ZSetup', {}),
    desc = 'Init z plugin.',
    once = true,
    callback = function()
      if vim.g.loaded_z then
        return
      end

      local z = require('plugin.z')
      z.setup()
      vim.keymap.set('n', '<Leader>z', z.select, {
        desc = 'Open a directory from z',
      })
    end,
  }

  vim.api.nvim_create_autocmd({ 'CmdlineEnter', 'DirChanged' }, opts)
  vim.api.nvim_create_autocmd(
    'UIEnter',
    vim.tbl_deep_extend('force', opts, {
      callback = vim.schedule_wrap(opts.callback),
    })
  )
  vim.api.nvim_create_autocmd(
    'CmdUndefined',
    vim.tbl_deep_extend('force', opts, { pattern = 'Z*' })
  )
end

-- addasync
vim.api.nvim_create_autocmd('InsertEnter', {
  group = vim.api.nvim_create_augroup('AddAsyncSetup', {}),
  desc = 'Init addasync plugin.',
  callback = function()
    if require('utils.ts').is_active() then
      require('plugin.addasync').setup()
      return true
    end
  end,
})

-- aider
if vim.g.loaded_aider == nil then
  -- stylua: ignore start
  local toggle = function() require('plugin.aider').toggle() end
  local send = function() require('plugin.aider').send() end
  local add = function() require('plugin.aider').add() end
  -- stylua: ignore end

  -- stylua: ignore start
  vim.keymap.set('n', '<Leader>@', toggle, { desc = 'Aider (AI) toggle chat panel' })
  vim.keymap.set('x', '<Leader>@', send, { desc = 'Aider (AI) send selection' })
  vim.keymap.set('x', '<Leader>+', send, { desc = 'Aider (AI) send selection' })
  vim.keymap.set('n', '<Leader>+', add, { desc = 'Aider (AI) add current file' })
  -- stylua: ignore end

  local opts = {
    group = vim.api.nvim_create_augroup('AiderSetup', {}),
    desc = 'Init aider plugin.',
    once = true,
    callback = function()
      if vim.fn.executable('aider') == 1 then
        require('plugin.aider').setup()
      end
    end,
  }

  vim.api.nvim_create_autocmd({ 'BufWritePre', 'CmdlineEnter' }, opts)
  vim.api.nvim_create_autocmd(
    'CmdUndefined',
    vim.tbl_deep_extend('force', opts, {
      pattern = 'Aider*',
    })
  )
end

-- session
if vim.g.loaded_session == nil then
  -- stylua: ignore start
  vim.keymap.set('n', '<Leader>w', function() require('plugin.session').select(true) end, { desc = 'Load session (workspace) interactively' })
  vim.keymap.set('n', '<Leader>W', function() require('plugin.session').load(nil, true) end, { desc = 'Load session (workspace) for cwd' })
  -- stylua: ignore end

  local opts = {
    desc = 'Init session plugin.',
    group = vim.api.nvim_create_augroup('SessionSetup', {}),
    once = true,
    callback = function()
      if vim.g.loaded_session ~= nil then
        return
      end

      ---@diagnostic disable-next-line: missing-fields
      require('plugin.session').setup({
        autoload = { enabled = false },
        autoremove = { enabled = false },
      })
    end,
  }

  vim.api.nvim_create_autocmd('CmdlineEnter', opts)
  vim.api.nvim_create_autocmd(
    'UIEnter',
    vim.tbl_deep_extend('force', opts, {
      callback = vim.schedule_wrap(opts.callback),
    })
  )
  vim.api.nvim_create_autocmd(
    'CmdUndefined',
    vim.tbl_deep_extend('force', opts, {
      pattern = { 'Session*', 'Mksession' },
    })
  )
end
