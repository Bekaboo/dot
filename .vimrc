""" Options {{{1
silent! set colorcolumn=80
silent! set laststatus=2
silent! set mouse=a
silent! set number
silent! set relativenumber
silent! set pumheight=16
silent! set ruler
silent! set scrolloff=4
silent! set sidescrolloff=8
silent! set showtabline=0
silent! set splitright
silent! set noswapfile
silent! set undofile
silent! set updatetime=10
silent! set nowrap
silent! set linebreak
silent! set breakindent
silent! set smoothscroll
silent! set completeopt=menuone
silent! set wildmenu
silent! set hlsearch
silent! set incsearch
silent! set ttimeoutlen=0
silent! set autowriteall
silent! set clipboard+=unnamedplus

silent! set backup
silent! set backupdir=~/.vimbackup
let s:backupdir = expand('~/.vimbackup')
if !isdirectory(s:backupdir)
  if filereadable(s:backupdir)
    call delete(s:backupdir)
  endif
  call mkdir(s:backupdir)
endif

silent! set list
silent! set listchars=tab:→\ ,trail:·,nbsp:␣,extends:…,precedes:…
silent! set fillchars=fold:·,diff:╱
silent! set conceallevel=2

silent! set tabstop=4
silent! set softtabstop=4
silent! set shiftwidth=4
silent! set expandtab
silent! set smartindent
silent! set autoindent

silent! set ignorecase
silent! set smartcase

silent! set spellcapcheck=''
silent! set spelllang=en_us
silent! set spellsuggest=best,9

syntax on
" }}}1

""" Abbreviations {{{1
" param: trig string
" param: command string
function s:_command_abbrev(trig, command) abort
  return getcmdtype() ==# ':'
          \ && getcmdline()[:getcmdpos() - 1]
          \ =~# '\(^\||\)\s*\V' . escape(a:trig, '\') . '\$'
        \ ? a:command
        \ : a:trig
endfunction

" Set abbreviation that only expand when the trigger is at the start of the
" command line or after a pipe '|', i.e. only when the trigger is at the
" position of a command
" param: trig string
" param: command string
" param: a:1 flags string? '<expr>'/'<buffer>',etc
function! s:command_abbrev(trig, command, ...) abort
  exe printf(
        \ 'cnoreabbrev %s %s <SID>_command_abbrev("%s", "%s")',
        \ '<expr>' . substitute(get(a:, 1, ''), '<expr>', '', ''),
        \ a:trig,
        \ escape(a:trig, '"\'),
        \ escape(a:command, '"\'))
endfunction

call s:command_abbrev('qa', 'qa!')
call s:command_abbrev('bw', 'bw!')
call s:command_abbrev('mks', 'mks!')
" }}}

""" Keymaps {{{1
let g:mapleader = ' '
let g:maplocalleader = ' '

nnoremap <expr> j v:count ? 'j' : 'gj'
nnoremap <expr> k v:count ? 'k' : 'gk'
xnoremap <expr> j v:count ? 'j' : 'gj'
xnoremap <expr> k v:count ? 'k' : 'gk'

nnoremap <silent> ]b :exec v:count1 . 'bn'<CR>
nnoremap <silent> [b :exec v:count1 . 'bp'<CR>

inoremap <C-L> <Esc>[szg`]a
inoremap <C-l> <C-g>u<Esc>[s1z=`]a<C-G>u

xmap a" 2i"
xmap a' 2i'
xmap a` 2i`
omap a" 2i"
omap a' 2i'
omap a` 2i`

" Text objects {{{2
" Current buffer (file)
xmap <silent> af :<C-u>silent! keepjumps normal! ggVG<CR>
xmap <silent> if :<C-u>silent! keepjumps normal! ggVG<CR>
omap <silent> af :silent! normal m`Vaf<CR>:silent! normal! ``<CR>
omap <silent> if :silent! normal m`Vif<CR>:silent! normal! ``<CR>

" Folds
" Returns the key sequence to select around/inside a fold,
" supposed to be called in visual mode
" param: motion 'i'|'a'
" return: string
function! s:textobj_fold(motion) abort
  let lnum = line('.')
  let sel_start = line('v')
  let foldlev = foldlevel(lnum)
  let foldlev_prev = foldlevel(lnum - 1)
  " Multi-line selection with cursor on top of selection
  if sel_start > lnum
    return (foldlev == 0 ? 'zk'
          \ : (foldlev > foldlev_prev && foldlev_prev ? 'k' : ''))
          \ . (a:motion == 'i' ? ']zkV[zj' : ']zV[z')
  endif
  return (foldlev == 0 ? 'zj'
        \ : (foldlev > foldlev_prev ? 'j' : ''))
        \ . (a:motion == 'i' ? '[zjV]zk' : '[zV]z')
endfunction
xmap <silent><expr> iz ':<C-u>silent! keepjumps normal! ' . <SID>textobj_fold('i') . '<CR>'
xmap <silent><expr> az ':<C-u>silent! keepjumps normal! ' . <SID>textobj_fold('a') . '<CR>'
omap <silent>       iz :silent! normal Viz<CR>
omap <silent>       az :silent! normal Vaz<CR>
" }}}2

" Nvim default mappings {{{2
nnoremap Y        y$
inoremap <C-u>    <C-g>u<C-u>
inoremap <C-w>    <C-g>u<C-w>
nnoremap <silent> <C-l> :nohlsearch\|diffupdate\|normal! <C-l><CR>
nnoremap <silent> &     :&&<CR>
xnoremap <silent> *     y/\V<C-R>=escape(@",'/')<CR><CR>
xnoremap <silent> #     y?\V<C-R>=escape(@",'/')<CR><CR>
" }}}2

" Window keymaps {{{2
for map in ['nnoremap', 'xnoremap']
  exe map . '<Esc>w       <C-w>W'
  exe map . '<Esc>h       <C-w>H'
  exe map . '<Esc>J       <C-w>J'
  exe map . '<Esc>K       <C-w>K'
  exe map . '<Esc>L       <C-w>L'
  exe map . '<Esc>=       <C-w>='
  exe map . '<Esc>_       <C-w>_'
  exe map . '<Esc><Bar>   <C-w>|'
  exe map . '<Esc><       <C-w><'
  exe map . '<Esc>p       <C-w>p'
  exe map . '<Esc>r       <C-w>r'
  exe map . '<Esc>v       <C-w>v'
  exe map . '<Esc>s       <C-w>s'
  exe map . '<Esc>x       <C-w>x'
  exe map . '<Esc>z       <C-w>z'
  exe map . '<Esc>c       <C-w>c'
  exe map . '<Esc>n       <C-w>n'
  exe map . '<Esc>o       <C-w>o'
  exe map . '<Esc>t       <C-w>t'
  exe map . '<Esc>T       <C-w>T'
  exe map . '<Esc>]       <C-w>]'
  exe map . '<Esc>^       <C-w>^'
  exe map . '<Esc>b       <C-w>b'
  exe map . '<Esc>d       <C-w>d'
  exe map . '<Esc>f       <C-w>f'
  exe map . '<Esc>}       <C-w>}'
  exe map . '<Esc>g]      <C-w>g]'
  exe map . '<Esc>g}      <C-w>g}'
  exe map . '<Esc>gf      <C-w>gf'
  exe map . '<Esc>gF      <C-w>gF'
  exe map . '<Esc>gt      <C-w>gt'
  exe map . '<Esc>gT      <C-w>gT'
  exe map . '<Esc>w       <C-w><C-w>'
  exe map . '<Esc>h       <C-w><C-h>'
  exe map . '<Esc>j       <C-w><C-j>'
  exe map . '<Esc>k       <C-w><C-k>'
  exe map . '<Esc>l       <C-w><C-l>'
  exe map . '<Esc>g<Esc>] <C-w>g<C-]>'
  exe map . '<Esc>g<Tab>  <C-w>g<Tab>'

  exe map . '<expr> <Esc>> v:count ? "<C-w>>" : "4<C-w>>"'
  exe map . '<expr> <Esc>< v:count ? "<C-w><" : "4<C-w><"'
  exe map . '<expr> <Esc>+ v:count ? "<C-w>+" : "2<C-w>+"'
  exe map . '<expr> <Esc>- v:count ? "<C-w>-" : "2<C-w>-"'
  exe map . '<expr> <C-w>> v:count ? "<C-w>>" : "4<C-w>>"'
  exe map . '<expr> <C-w>< v:count ? "<C-w><" : "4<C-w><"'
  exe map . '<expr> <C-w>+ v:count ? "<C-w>+" : "2<C-w>+"'
  exe map . '<expr> <C-w>- v:count ? "<C-w>-" : "2<C-w>-"'
endfor
" }}}2

" Readline keymaps {{{2
noremap! <C-a> <Home>
noremap! <C-e> <End>
noremap! <C-d> <Del>
noremap! <expr> <C-y> pumvisible() ? "<C-y>" : "<C-r>-"
cnoremap <C-b> <Left>
cnoremap <C-f> <Right>
cnoremap <C-k> <C-\>e(strpart(getcmdline(), 0, getcmdpos() - 1))<CR>
noremap! <Esc>[3;3~ <C-w>

" Match non-empty string
" param: str string
" vararg: string patterns to match
" return: string
function! s:match_nonempty(str, ...) abort
  let capture = ''
  for pattern in a:000
    let capture = matchstr(a:str, pattern)
    if capture =~# '\S'
      return capture
    endif
  endfor
  return capture
endfunction

" Get current line
" return: string
function! s:get_current_line() abort
  return mode() ==# 'c' ? getcmdline() : getline('.')
endfunction

" Get current column number
" return: integer
function! s:get_current_col() abort
  return mode() ==# 'c' ? getcmdpos() : col('.')
endfunction

" Get character relative to cursor
" param: offset number from cursor
" return: string character
function! s:get_char(offset) abort
  return s:get_current_line()[s:get_current_col() + a:offset - 1]
endfunction

" Get word after cursor
" param: a:1 str string? content of the line, default to current line
" param: a:2 colnr integer? column number, default to current column
" return: string
function! s:get_word_after(...) abort
  let str = get(a:, 1, s:get_current_line())
  let colnr = get(a:, 2, s:get_current_col())
  return s:match_nonempty(str[colnr - 1:], '^\s*\w*', '^\s*[^\ \t0-9A-Za-z_]*')
endfunction

" Get word before cursor
" param: a:1 str string? content of the line, default to current line
" param: a:2 colnr integer? column number, default to current column - 1
" return: string
function! s:get_word_before(...) abort
  let str = get(a:, 1, s:get_current_line())
  let colnr = get(a:, 2, s:get_current_col() - 1)
  return colnr == 0 ? '' : s:match_nonempty(
        \ str[:colnr - 1],
        \ '\w*\s*$',
        \ '[^\ \t0-9A-Za-z_]*\s*$')
endfunction

" Check if current line is the last line
" return: 0/1
function! s:last_line() abort
  return mode() ==# 'c' || line('.') == line('$')
endfunction

" Check if current line is the first line
" return: 0/1
function! s:first_line() abort
  return mode() ==# 'c' || line('.') == 1
endfunction

" Check if cursor is at the end of the line
" return: 0/1
function! s:end_of_line() abort
  return s:get_current_col() == strlen(s:get_current_line()) + 1
endfunction

" Check if cursor is at the start of the line
" return: 0/1
function! s:start_of_line() abort
  return s:get_current_col() == 1
endfunction

" Check if cursor is at the middle of the line
" return: 0/1
function! s:mid_of_line() abort
  let current_col = s:get_current_col()
  return current_col > 1 && current_col <= strlen(s:get_current_line())
endfunction

function! s:i_ctrl_b() abort
  if s:first_line() && s:start_of_line()
    return "\<Ignore>"
  endif
  return s:start_of_line() ? "\<Up>\<End>" : "\<Left>"
endfunction

function! s:i_ctrl_f() abort
  if s:last_line() && s:end_of_line()
    return "\<Ignore>"
  endif
  return s:end_of_line() ? "\<Down>\<Home>" : "\<Right>"
endfunction

function! s:i_ctrl_k() abort
  return s:end_of_line() ? "\<C-g>u\<Del>" : "\<Esc>\<Right>Da"
endfunction

function! s:ic_ctrl_t() abort
  let cmdtype = getcmdtype()
  if cmdtype =~# '[?/]'
    return "\<C-t>"
  endif
  if s:start_of_line() && !first_line()
    let char_under_cur = s:get_char(0)
    if char_under_cur !=# ''
      return "\<Del>\<Up>\<End>" . char_under_cur . "\<Down>\<Home>"
    else
      let prev_line = getline(line(".") - 1)
      let char_end_of_prev_line = prev_line[-1:]
      if char_end_of_prev_line !=# ''
        return "\<Up>\<End>\<BS>\<Down>\<Home>" . char_end_of_prev_line
      endif
      return ''
    endif
  endif
  if s:end_of_line()
    let  char_before = s:get_char(-1)
    if s:get_char(-2) !=# '' || mode() ==# 'c'
      return "\<BS>\<Left>" . char_before . "\<End>"
    else
      return "\<BS>\<Up>\<End>" . char_before . "\<Down>\<End>"
    endif
  endif
  if s:mid_of_line()
    return "\<BS>\<Right>" . s:get_char(-1)
  endif
endfunction

function! s:ic_ctrl_u() abort
  if !s:start_of_line()
    call setreg('-', s:get_current_line()[:s:get_current_col() - 2])
  endif
  return mode() ==# 'c' ? "\<C-u>" : "\<C-g>u\<C-u>"
endfunction

function! s:ic_meta_b() abort
  let word_before = s:get_word_before()
  if word_before =~# '\S' || mode() ==# 'c'
    return repeat("\<Left>", strlen(word_before))
  endif
  " No word before cursor and is in insert mode
  let current_linenr = line('.')
  let target_linenr = prevnonblank(current_linenr - 1)
  let target_linenr = target_linenr ? target_linenr : 1
  let line_str = getline(target_linenr)
  return (current_linenr == target_linenr ? '' : "\<End>")
        \ . repeat("\<Up>", current_linenr - target_linenr)
        \ . repeat("\<Left>", strlen(s:get_word_before(line_str, strlen(line_str))))
endfunction

function! s:ic_meta_f() abort
  let word_after = s:get_word_after()
  if word_after =~# '\S' || mode() ==# 'c'
    return repeat("\<Right>", strlen(word_after))
  endif
  " No word after cursor and is in insert mode
  let current_linenr = line('.')
  let target_linenr = nextnonblank(current_linenr + 1)
  let target_linenr = target_linenr ? target_linenr : line('$')
  let line_str = getline(target_linenr)
  return (current_linenr == target_linenr ? '' : "\<Home>")
        \ . repeat("\<Down>", target_linenr - current_linenr)
        \ . repeat("\<Right>", strlen(s:get_word_after(line_str, 1)))
endfunction

function! s:ic_meta_d() abort
  return (mode() == 'c' ? '' : "\<C-g>u")
        \ . repeat("\<Del>", strlen(s:get_word_after()))
endfunction

inoremap <expr> <C-b>  <SID>i_ctrl_b()
inoremap <expr> <C-f>  <SID>i_ctrl_f()
inoremap <expr> <C-k>  <SID>i_ctrl_k()
noremap! <expr> <C-t>  <SID>ic_ctrl_t()
noremap! <expr> <C-u>  <SID>ic_ctrl_u()
noremap! <expr> <Esc>f <SID>ic_meta_f()
noremap! <expr> <Esc>d <SID>ic_meta_d()
noremap! <expr> <Esc>b <SID>ic_meta_b()
" }}}2
" }}}1

""" Autocmds {{{1
augroup AutoSave
  au!
  au BufLeave,WinLeave,FocusLost * ++nested silent! wall
augroup END

augroup EqualWinSize
  au!
  au VimResized * wincmd =
augroup END

augroup TextwidthRelativeColorcolumn
  au!
  au OptionSet textwidth if v:option_new | setlocal cc=+1 | endif
augroup END

augroup LastPosJmp
  au!
  au BufReadPost * if &ft !=# 'gitcommit' && &ft !=# 'gitrebase' |
        \ exe 'silent! normal! g`"' |
        \ endif
augroup END

" Update folds for given buffer
" param: bufnr integer
function! s:update_folds_once(bufnr)
  if !getbufvar(a:bufnr, 'foldupdated', 0)
    call setbufvar(a:bufnr, 'foldupdated', 1)
    exe 'normal! zx'
  endif
endfunction

augroup UpdateFolds
  au!
  au BufWinEnter * :call s:update_folds_once(expand('<abuf>'))
  au BufUnload   * :call setbufvar(expand('<abuf>'), 'foldupdated', 0)
augroup END
" }}}1

""" Misc {{{1
" Workaround to prevent <Esc> lag cause by Meta keymaps
noremap  <nowait> <Esc> <Esc>
noremap! <nowait> <Esc> <C-\><C-n>
" }}}1

" vim:tw=79:ts=2:sts=2:sw=2:et:fdm=marker:ft=vim:norl:
