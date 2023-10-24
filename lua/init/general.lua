local g = vim.g
local opt = vim.opt

-- stylua: ignore start
opt.cursorline     = true
opt.colorcolumn    = '80'
opt.foldlevelstart = 99
opt.guifont        = 'JetbrainsMono Nerd Font:h13'
opt.helpheight     = 10
opt.laststatus     = 3
opt.showmode       = false
opt.mouse          = 'a'
opt.mousemoveevent = true
opt.number         = true
opt.pumheight      = 16
opt.relativenumber = true
opt.ruler          = true
opt.scrolloff      = 4
opt.sidescrolloff  = 8
opt.signcolumn     = 'yes:1'
opt.splitright     = true
opt.splitbelow     = true
opt.swapfile       = false
opt.termguicolors  = true
opt.undofile       = true
opt.updatetime     = 10
opt.wrap           = false
opt.linebreak      = true
opt.breakindent    = true -- Freeze nvim when editing long line with &wrap set
opt.smoothscroll   = true
opt.completeopt    = 'menuone'
opt.conceallevel   = 2
opt.concealcursor  = 'nc'
opt.autowriteall   = true
opt.virtualedit    = 'block'
-- stylua: ignore end

-- Cursor shape
-- For unknown reasons, wezterm won't reload config for current session
-- when we spawn 'setbg' or 'setcolors' scripts from nvim using libuv
-- if GUI cursor highlights are set for modes n,v,r,cr
opt.gcr = vim.env.WEZTERM_PANE
    and 'n-v:block,i-c-ci-ve:blinkoff500-blinkon500-block-TermCursor,r-cr:hor20,o:hor50'
  or 'n-v:block-Cursor/lCursor,i-c-ci-ve:blinkoff500-blinkon500-block-TermCursor,r-cr:hor20,o:hor50-Cursor/lCursor'

-- Use patience algorithm for diffing
opt.diffopt:append('algorithm:patience')

-- Use system clipboard
opt.clipboard:append('unnamedplus')

opt.backup = true
opt.backupdir:remove('.')

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
  eob       = ' ',
}

opt.ts          = 4
opt.softtabstop = 4
opt.shiftwidth  = 4
opt.expandtab   = true
opt.smartindent = true
opt.autoindent  = true

opt.ignorecase  = true
opt.smartcase   = true

opt.spell         = true
opt.spellcapcheck = ''
opt.spelllang     = 'en,cjk'
opt.spelloptions  = 'camel'
opt.spellsuggest  = 'best,9'

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
-- stylua: ignore end
