-- Lazy-load builtin plugins

-- vscode-neovim
if vim.g.vscode then
  vim.fn['plugin#vscode#setup']()
  return
end

local load = require('utils.load')

-- expandtab
load.on_events('InsertEnter', function()
  require('plugin.expandtab').setup()
end)

-- jupytext
load.on_events({ event = 'BufReadCmd', pattern = '*.ipynb' }, function(args)
  require('plugin.jupytext').setup(args.buf)
end)

-- lsp & diagnostic commands
load.on_events(
  { 'Syntax', 'FileType', 'LspAttach', 'DiagnosticChanged' },
  function()
    require('plugin.lsp-commands').setup()
  end
)

-- readline
load.on_events({ 'CmdlineEnter', 'InsertEnter' }, function()
  require('plugin.readline').setup()
end)

-- winbar
load.on_events('FileType', function()
  if vim.g.loaded_winbar ~= nil then
    return
  end

  local winbar = require('plugin.winbar')
  local api = require('plugin.winbar.api')
  winbar.setup({ bar = { hover = false } })

  vim.keymap.set(
    'n',
    '<Leader>;',
    api.pick,
    { desc = 'Pick symbols in winbar' }
  )
  vim.keymap.set(
    'n',
    '[;',
    api.goto_context_start,
    { desc = 'Go to start of current context' }
  )
  vim.keymap.set(
    'n',
    '];',
    api.select_next_context,
    { desc = 'Select next context' }
  )
end)

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
load.on_events('TermOpen', function(args)
  local term = require('plugin.term')
  term.setup()
  vim.keymap.set('n', '.', term.rerun, {
    buffer = args.buf,
    desc = 'Re-run terminal job',
  })
end)

-- tmux
if vim.g.has_ui then
  load.on_events({ event = 'UIEnter', schedule = true }, function()
    require('plugin.tmux').setup()
  end)
end

-- tabout
load.on_events('InsertEnter', function()
  require('plugin.tabout').setup()
end)

-- z
if vim.g.loaded_z == nil then
  vim.keymap.set('n', '<Leader>z', function()
    require('plugin.z').select()
  end, { desc = 'Open a directory from z' })

  load.on_events({
    'CmdlineEnter',
    'DirChanged',
    { event = 'UIEnter', schedule = true },
    { event = 'CmdUndefined', pattern = 'Z*' },
  }, function()
    require('plugin.z').setup()
  end)
end

-- addasync
load.on_events('InsertEnter', function()
  if require('utils.ts').is_active() then
    require('plugin.addasync').setup()
  end
end)

-- session
if vim.g.loaded_session == nil then
  vim.keymap.set('n', '<Leader>w', function()
    require('plugin.session').select(true)
  end, { desc = 'Load session (workspace) interactively' })

  vim.keymap.set('n', '<Leader>W', function()
    require('plugin.session').load(nil, true)
  end, { desc = 'Load session (workspace) for cwd' })

  load.on_events({
    'CmdlineEnter',
    { event = 'UIEnter', schedule = true },
    { event = 'CmdUndefined', pattern = { 'Session*', 'Mksession' } },
  }, function()
    require('plugin.session').setup({
      autoload = { enabled = false },
      autoremove = { enabled = false },
    })
  end)
end
