local cmd = vim.cmd
local fn = vim.fn
local g = vim.g
local opt = vim.opt

-- stylua: ignore start
opt.cursorline     = true
opt.colorcolumn    = '80'
opt.eb             = false
opt.foldlevelstart = 99
opt.guifont        = 'JetbrainsMono Nerd Font:h13'
opt.laststatus     = 3
opt.mouse          = 'a'
opt.number         = true
opt.pumheight      = 16
opt.relativenumber = true
opt.ruler          = true
opt.scrolloff      = 4
opt.sidescrolloff  = 8
opt.showtabline    = 0
opt.signcolumn     = 'yes:1'
opt.splitright     = true
opt.swapfile       = false
opt.termguicolors  = true
opt.undofile       = true
opt.updatetime     = 10
opt.vb             = true
opt.wrap           = false
opt.completeopt    = 'menuone'
opt.conceallevel   = 2
-- stylua: ignore end

-- Cursor shape
-- opt.gcr = 'n-v:block,i-c-ci-ve:blinkoff500-blinkon500-block,r-cr-o:hor20'
opt.gcr:append('n-v:block-Cursor/lCursor')
opt.gcr:append('i-c-ci-ve:blinkoff500-blinkon500-block-TermCursor/lCursor')
opt.gcr:append('r-cr:hor20,o:hor50')

opt.backup = true
opt.backupdir = fn.stdpath('data') .. '/backup//'

-- stylua: ignore start
opt.list = true
opt.listchars = {
  tab      = '→ ',
  extends  = '…',
  precedes = '…',
  nbsp     = '␣',
  trail    = '·',
}
opt.fillchars = {
  fold      = '·',
  foldopen  = '',
  foldclose = '',
  foldsep   = ' ',
  diff      = '╱',
}

opt.ts          = 4
opt.softtabstop = 4
opt.shiftwidth  = 4
opt.expandtab   = true
opt.smartindent = true
opt.autoindent  = true

opt.hlsearch    = false
opt.ignorecase  = true
opt.smartcase   = true

opt.spellcapcheck = ''
opt.spelllang = 'en,cjk'
opt.spelloptions = 'camel'
opt.spellsuggest = 'best,9'

-- disable plugins shipped with neovim
g.loaded_gzip            = 1
g.loaded_tar             = 1
g.loaded_tarPlugin       = 1
g.loaded_zip             = 1
g.loaded_zipPlugin       = 1
g.loaded_getscript       = 1
g.loaded_getscriptPlugin = 1
g.loaded_vimball         = 1
g.loaded_vimballPlugin   = 1
g.loaded_matchit         = 1
g.loaded_2html_plugin    = 1
g.loaded_logiPat         = 1
g.loaded_rrhelper        = 1
g.loaded_netrw           = 1
g.loaded_netrwPlugin     = 1
-- stylua: ignore start

-- colorscheme
cmd('colorscheme cockatoo')

-- abbreviations
cmd('cnoreabbrev qa qa!')
cmd('cnoreabbrev bw bw!')
cmd('cnoreabbrev mks mks!')
