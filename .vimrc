" Options
set cursorline
set cursorlineopt=number
set colorcolumn=80
set noeb
set vb
set foldlevelstart=99
set guifont=JetbrainsMono\ Nerd\ Font:h13
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
set hlsearch
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
set fillchars=fold:·,foldopen:,foldclose:,foldsep:\ ,diff:╱
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
set spelloptions=camel
set spellsuggest=best,9

cnoreabbrev qa qa!
cnoreabbrev bw bw!
cnoreabbrev mks mks!

syntax on
colors habamax

" Keymaps
let g:mapleader = ' '
let g:maplocalleader = ' '
nnoremap W       <C-w>W
nnoremap H       <C-w>H
nnoremap J       <C-w>J
nnoremap K       <C-w>K
nnoremap L       <C-w>L
nnoremap =       <C-w>=
nnoremap -       <C-w>-
nnoremap +       <C-w>+
nnoremap _       <C-w>_
nnoremap <Bar>   <C-w><Bar>
nnoremap <       <C-w><
nnoremap >       <C-w>>
nnoremap p       <C-w>p
nnoremap r       <C-w>r
nnoremap v       <C-w>v
nnoremap s       <C-w>s
nnoremap x       <C-w>x
nnoremap z       <C-w>z
nnoremap c       <C-w>c
nnoremap n       <C-w>n
nnoremap o       <C-w>o
nnoremap t       <C-w>t
nnoremap T       <C-w>T
nnoremap ]       <C-w>]
nnoremap ^       <C-w>^
nnoremap b       <C-w>b
nnoremap d       <C-w>d
nnoremap f       <C-w>f
nnoremap }       <C-w>}
nnoremap g]      <C-w>g]
nnoremap g}      <C-w>g}
nnoremap gf      <C-w>gf
nnoremap gF      <C-w>gF
nnoremap gt      <C-w>gt
nnoremap gT      <C-w>gT
nnoremap w       <C-w><C-w>
nnoremap h       <C-w><C-h>
nnoremap j       <C-w><C-j>
nnoremap k       <C-w><C-k>
nnoremap l       <C-w><C-l>
nnoremap g]    <C-w>g<C-]>
nnoremap g<Tab>  <C-w>g<Tab>

xnoremap W       <C-w>W
xnoremap H       <C-w>H
xnoremap J       <C-w>J
xnoremap K       <C-w>K
xnoremap L       <C-w>L
xnoremap =       <C-w>=
xnoremap -       <C-w>-
xnoremap +       <C-w>+
xnoremap _       <C-w>_
xnoremap <Bar>   <C-w><Bar>
xnoremap <       <C-w><
xnoremap >       <C-w>>
xnoremap p       <C-w>p
xnoremap r       <C-w>r
xnoremap v       <C-w>v
xnoremap s       <C-w>s
xnoremap x       <C-w>x
xnoremap z       <C-w>z
xnoremap c       <C-w>c
xnoremap n       <C-w>n
xnoremap o       <C-w>o
xnoremap t       <C-w>t
xnoremap T       <C-w>T
xnoremap ]       <C-w>]
xnoremap ^       <C-w>^
xnoremap b       <C-w>b
xnoremap d       <C-w>d
xnoremap f       <C-w>f
xnoremap }       <C-w>}
xnoremap g]      <C-w>g]
xnoremap g}      <C-w>g}
xnoremap gf      <C-w>gf
xnoremap gF      <C-w>gF
xnoremap gt      <C-w>gt
xnoremap gT      <C-w>gT
xnoremap w       <C-w><C-w>
xnoremap h       <C-w><C-h>
xnoremap j       <C-w><C-j>
xnoremap k       <C-w><C-k>
xnoremap l       <C-w><C-l>
xnoremap g]    <C-w>g<C-]>
xnoremap g<Tab>  <C-w>g<Tab>

nnoremap <expr> j v:count ? 'j' : 'gj'
nnoremap <expr> k v:count ? 'k' : 'gk'

nnoremap ]b <Cmd>exec v:count1 . 'bn'<CR>
nnoremap [b <Cmd>exec v:count1 . 'bp'<CR>

inoremap <C-L> <Esc>[szg`]a
inoremap <C-l> <C-G>u<Esc>[s1z=`]a<C-G>u

xmap af :<C-u>keepjumps silent! normal! ggVG<CR>
xmap if :<C-u>keepjumps silent! normal! ggVG<CR>
omap af <Cmd>silent! normal m`Vaf<CR><Cmd>silent! normal! ``<CR>
omap if <Cmd>silent! normal m`Vif<CR><Cmd>silent! normal! ``<CR>

" TODO: Readline keymaps
" ...
