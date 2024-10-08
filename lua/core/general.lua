-- Enable faster lua loader using byte-compilation
-- https://github.com/neovim/neovim/commit/2257ade3dc2daab5ee12d27807c0b3bcf103cd29
vim.loader.enable()

local g = vim.g
local opt = vim.opt
local env = vim.env

g.has_ui = #vim.api.nvim_list_uis() > 0
g.has_gui = vim.fn.has('gui_running') == 1
g.modern_ui = g.has_ui and env.DISPLAY ~= nil
g.nf = g.modern_ui and env.NVIM_NF and true or false

opt.timeout = false
opt.colorcolumn = '+1'
opt.cursorlineopt = 'number'
opt.cursorline = true
opt.foldlevelstart = 99
opt.foldtext = ''
opt.helpheight = 10
opt.showmode = false
opt.mousemoveevent = true
opt.number = true
opt.ruler = true
opt.pumheight = 16
opt.scrolloff = 4
opt.sidescrolloff = 8
opt.signcolumn = 'yes:1'
opt.splitright = true
opt.splitbelow = true
opt.swapfile = false
opt.undofile = true
opt.wrap = false
opt.linebreak = true
opt.breakindent = true
opt.smoothscroll = true
opt.ignorecase = true
opt.smartcase = true
opt.autoindent = true
opt.autowriteall = true
opt.completeopt = 'menuone'
opt.jumpoptions = 'stack,view'

-- nvim 0.10.0 automatically enables termguicolors. When using nvim inside
-- tmux in Linux tty, where $TERM is set to 'tmux-256color' but $DISPLAY is
-- not set, termguicolors is automatically set. This is undesirable, so we
-- need to explicitly disable it in this case
if not g.modern_ui then
  opt.termguicolors = false
end

---Restore 'shada' option and read from shada once
---@return true
local function _rshada()
  vim.cmd.set('shada&')
  pcall(vim.cmd.rshada)
  return true
end

opt.shada = ''
vim.defer_fn(_rshada, 100)
vim.api.nvim_create_autocmd('BufReadPre', { once = true, callback = _rshada })

-- Recognize numbered lists when formatting text
opt.formatoptions:append('n')

-- Spell check
vim.opt.spell = true
vim.opt.spellcapcheck = ''
vim.opt.spelllang = 'en,cjk'
vim.opt.spelloptions = 'camel'
vim.opt.spellsuggest = 'best,9'

-- Cursor shape
opt.gcr = {
  'i-c-ci-ve:blinkoff500-blinkon500-block-TermCursor',
  'n-v:block-Curosr/lCursor',
  'o:hor50-Curosr/lCursor',
  'r-cr:hor20-Curosr/lCursor',
}

-- Use histogram algorithm for diffing, generates more readable diffs in
-- situations where two lines are swapped
opt.diffopt:append({
  'algorithm:histogram',
  'indent-heuristic',
})

-- Use system clipboard
opt.clipboard:append('unnamedplus')

-- Align columns in quickfix window
opt.quickfixtextfunc = [[v:lua.require'utils.misc'.qftf]]

opt.backup = true
opt.backupdir:remove('.')

opt.list = true
opt.listchars = {
  tab = '  ',
  trail = '·',
}
opt.fillchars = {
  fold = '·',
  foldsep = ' ',
  eob = ' ',
}
if g.modern_ui then
  opt.conceallevel = 2
  opt.listchars:append({ nbsp = '␣' })
  opt.fillchars:append({ diff = '╱' })
end
if g.nf then
  opt.fillchars:append({
    foldopen = '',
    foldclose = '',
  })
end

-- Netrw settings
g.netrw_banner = 0
g.netrw_cursor = 5
g.netrw_keepdir = 0
g.netrw_keepj = ''
g.netrw_list_hide = [[\(^\|\s\s\)\zs\.\S\+]]
g.netrw_liststyle = 1
g.netrw_localcopydircmd = 'cp -r'

-- Fzf settings
g.fzf_layout = {
  window = {
    width = 0.7,
    height = 0.7,
    pos = 'center',
  },
}
env.FZF_DEFAULT_OPTS = (env.FZF_DEFAULT_OPTS or '')
  .. ' --border=sharp --margin=0 --padding=0'

---Lazy-load runtime files
---@param runtime string
---@param flag string
---@param events string|string[]
local function _load(runtime, flag, events)
  if g[flag] and g[flag] ~= 0 then
    return
  end

  g[flag] = 0
  if type(events) == 'string' then
    events = { events }
  end

  local gid = vim.api.nvim_create_augroup('Load_' .. runtime, {})
  for _, e in
    ipairs(vim.tbl_map(function(e)
      return vim.split(e, ' ', {
        trimempty = true,
        plain = true,
      })
    end, events))
  do
    vim.api.nvim_create_autocmd(e[1], {
      once = true,
      pattern = e[2],
      group = gid,
      callback = function()
        if g[flag] == 0 then
          g[flag] = nil
          vim.cmd.runtime(runtime)
        end
        vim.api.nvim_del_augroup_by_id(gid)
        return true
      end,
    })
  end
end

_load('plugin/rplugin.vim', 'loaded_remote_plugins', {
  'FileType',
  'BufNew',
  'BufWritePost',
  'BufReadPre',
})
_load('provider/python3.vim', 'loaded_python3_provider', {
  'FileType python',
  'BufNew *.py,*.ipynb',
  'BufEnter *.py,*.ipynb',
  'BufWritePost *.py,*.ipynb',
  'BufReadPre *.py,*.ipynb',
})
