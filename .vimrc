""" Options
set colorcolumn=80
set noeb
set vb
set foldlevelstart=99
set laststatus=2
set mouse=a
set number
set relativenumber
set pumheight=16
set ruler
set scrolloff=4
set sidescrolloff=8
set showtabline=0
set splitright
set noswapfile
set undofile
set updatetime=10
set nowrap
set completeopt=menuone
set wildmenu
set ttimeoutlen=0

set backup
set backupdir=~/.vimbackup
let s:backupdir_full = expand('~/.vimbackup')
if !isdirectory(s:backupdir_full)
    if filereadable(s:backupdir_full)
        call delete(s:backupdir_full)
    endif
    call mkdir(s:backupdir_full)
endif

set list
set listchars=tab:→\ ,trail:·,nbsp:␣,extends:…,precedes:…
set fillchars=fold:·,diff:╱
set conceallevel=2

set tabstop=4
set softtabstop=4
set shiftwidth=4
set expandtab
set smartindent
set autoindent

set ignorecase
set smartcase

set spellcapcheck=''
set spelllang=en_us
set spellsuggest=best,9

syntax on

""" Abbreviations
cnoreabbrev qa qa!
cnoreabbrev bw bw!
cnoreabbrev mks mks!

""" Keymaps
let g:mapleader = ' '
let g:maplocalleader = ' '

nnoremap <expr> j v:count ? 'j' : 'gj'
nnoremap <expr> k v:count ? 'k' : 'gk'

nnoremap ]b :exec v:count1 . 'bn'<CR>
nnoremap [b :exec v:count1 . 'bp'<CR>

inoremap <C-L> <Esc>[szg`]a
inoremap <C-l> <C-G>u<Esc>[s1z=`]a<C-G>u

xmap af :<C-u>keepjumps silent! normal! ggVG<CR>
xmap if :<C-u>keepjumps silent! normal! ggVG<CR>
omap af :silent! normal m`Vaf<CR>:silent! normal! ``<CR>
omap if :silent! normal m`Vif<CR>:silent! normal! ``<CR>

""" Combos
" Hlsearch settings
" <Cmd>...<CR> won't work with vim 7.4
set nohlsearch
set incsearch

nnoremap <silent><C-l> <C-l>:set nohlsearch<CR>

nnoremap <silent>n  n:set hlsearch<CR>
nnoremap <silent>N  N:set hlsearch<CR>
nnoremap <silent>*  *:set hlsearch<CR>
nnoremap <silent>#  #:set hlsearch<CR>
nnoremap <silent>/  /:set hlsearch<CR>
nnoremap <silent>?  ?:set hlsearch<CR>
nnoremap <silent>g* g*:set hlsearch<CR>
nnoremap <silent>g# g#:set hlsearch<CR>

xnoremap <silent>n  n:set hlsearch<CR>n
xnoremap <silent>N  N:set hlsearch<CR>N
xnoremap <silent>*  *:set hlsearch<CR>*
xnoremap <silent>#  #:set hlsearch<CR>#
xnoremap <silent>/  /:set hlsearch<CR>/
xnoremap <silent>?  ?:set hlsearch<CR>?
xnoremap <silent>g* g*:set hlsearch<CR>g*
xnoremap <silent>g# g#:set hlsearch<CR>g#

augroup AutoHlSearch
    au!
    au InsertEnter * set nohlsearch
augroup END
