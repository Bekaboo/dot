-- Lazy-load builtin plugins

-- vscode-neovim
if vim.g.vscode then
  vim.fn['my#plugin#vscode#setup']()
  return
end

local load = require('my.utils.load')

-- expandtab
load.on_events('InsertEnter', 'plugin.expandtab', function()
  require('my.plugin.expandtab').setup()
end)

-- jupytext
load.on_events(
  { event = 'BufReadCmd', pattern = '*.ipynb' },
  'plugin.jupytext',
  function()
    require('my.plugin.jupytext').setup()
  end
)

-- lsp & diagnostic commands
load.on_events(
  { 'Syntax', 'FileType', 'LspAttach', 'DiagnosticChanged' },
  'plugin.lsp-commands',
  function()
    require('my.plugin.lsp-commands').setup()
  end
)

-- readline
load.on_events({ 'CmdlineEnter', 'InsertEnter' }, 'plugin.readline', function()
  require('my.plugin.readline').setup()
end)

-- winbar
load.on_events('FileType', 'plugin.winbar', function()
  if vim.g.loaded_winbar ~= nil then
    return
  end

  require('my.plugin.winbar').setup({
    bar = { hover = false },
  })

  local winbar_api = require('my.plugin.winbar.api')
  vim.keymap.set(
    'n',
    '<Leader>;',
    winbar_api.pick,
    { desc = 'Pick symbols in winbar' }
  )
  vim.keymap.set(
    'n',
    '[;',
    winbar_api.goto_context_start,
    { desc = 'Go to start of current context' }
  )
  vim.keymap.set(
    'n',
    '];',
    winbar_api.select_next_context,
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
  vim.opt[name] = string.format("%%!v:lua.require'my.plugin.%s'()", name)
end

load_ui('tabline')
load_ui('statusline')
load_ui('statuscolumn')

-- term
load.on_events('TermOpen', 'plugin.term', function(args)
  local term = require('my.plugin.term')
  term.setup()
  vim.keymap.set('n', '.', term.rerun, {
    buffer = args.buf,
    desc = 'Re-run terminal job',
  })
end)

-- tmux
if vim.g.has_ui then
  load.on_events(
    { event = 'UIEnter' },
    'plugin.tmux',
    vim.schedule_wrap(function()
      require('my.plugin.tmux').setup()
    end)
  )
end

-- tabout
load.on_events('InsertEnter', 'plugin.tabout', function()
  require('my.plugin.tabout').setup()
end)

-- z
if vim.g.loaded_z == nil then
  vim.keymap.set('n', '<Leader>z', function()
    require('my.plugin.z').select()
  end, { desc = 'Open a directory from z' })

  local function setup()
    require('my.plugin.z').setup()
  end

  load.on_events('UIEnter', 'plugin.z', vim.schedule_wrap(setup))
  load.on_events('DirChanged', 'plugin.z', setup)
  load.on_cmds({ 'Z', 'ZSelect' }, 'plugin.z', setup)
end

-- addasync
load.on_events('InsertEnter', 'plugin.addaync', function()
  require('my.plugin.addasync').setup()
end)

-- session
if vim.g.loaded_session == nil then
  vim.keymap.set('n', '<Leader>w', function()
    require('my.plugin.session').select(true)
  end, { desc = 'Load session (workspace) interactively' })

  vim.keymap.set('n', '<Leader>W', function()
    require('my.plugin.session').load(nil, true)
  end, { desc = 'Load session (workspace) for cwd' })

  local function setup()
    require('my.plugin.session').setup({
      autoload = { enabled = false },
      autoremove = { enabled = false },
    })
  end

  load.on_events('BufRead', 'plugin.session', setup)
  load.on_cmds({
    'SessionLoad',
    'SessionSave',
    'SessionRemove',
    'SessionSelect',
    'Mkssession',
  }, 'plugin.session', setup)
end
