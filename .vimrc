""" Options {{{1
silent! set hidden
silent! set foldlevelstart=99
silent! set colorcolumn=80
silent! set helpheight=10
silent! set laststatus=2
silent! set mouse=a
silent! set number
silent! set pumheight=16
silent! set ruler
silent! set scrolloff=4
silent! set sidescrolloff=8
silent! set showtabline=1
silent! set splitright
silent! set splitbelow
silent! set nostartofline
silent! set noswapfile
silent! set undofile
silent! set updatetime=10
silent! set nowrap
silent! set linebreak
silent! set breakindent
silent! set smoothscroll
silent! set completeopt=menuone
silent! set wildmenu
silent! set wildoptions+=fuzzy,pum
silent! set hlsearch
silent! set incsearch
silent! set ttimeoutlen=0
silent! set autowriteall
silent! set virtualedit=block
silent! set shortmess-=S
silent! set sessionoptions+=globals
silent! set viminfo=!,'100,<50,s10,h
silent! set diffopt+=algorithm:histogram
silent! set clipboard^=unnamedplus
silent! set formatoptions+=n

" Focus events
silent! let &t_fe = "\<Esc>[?1004h"
silent! let &t_fd = "\<Esc>[?1004l"

" Set editor to vim
silent! let $EDITOR = 'vim'
silent! let $VISUAL = 'vim'

silent! set backup
silent! set backupdir=~/.vimbackup
let s:backupdir = expand('~/.vimbackup')
if !isdirectory(s:backupdir)
  if filereadable(s:backupdir)
    call delete(s:backupdir)
  endif
  call mkdir(s:backupdir)
endif

silent! set fillchars=fold:·,diff:╱
silent! set conceallevel=2

silent! set tabstop=4
silent! set softtabstop=4
silent! set shiftwidth=4
silent! set expandtab
silent! set cindent
silent! set autoindent

silent! set ignorecase
silent! set smartcase

silent! set spell
silent! set spellcapcheck=''
silent! set spelllang=en_us
silent! set spelloptions=camel
silent! set spellsuggest=best,9

syntax on
filetype plugin indent on
" }}}1

""" Abbreviations {{{1
" Set abbreviation that only when the trigger is at the position of a command
" param: trig string
" param: command string
" param: a:1 flags string? '<expr>'/'<buffer>',etc
function! s:command_abbrev(trig, command, ...) abort
  if exists('*getcmdcompltype')
    exe printf(
          \ 'cnoreabbrev %s %s getcmdcompltype() ==# "command" ? "%s" : "%s"',
          \ '<expr>' . substitute(get(a:, 1, ''), '<expr>', '', ''),
          \ a:trig,
          \ escape(a:command, '"\'),
          \ escape(a:trig, '"\'))
  endif
endfunction

call s:command_abbrev('S', '%s')
call s:command_abbrev('ep', 'e%:p:h')
call s:command_abbrev('xp', 'sp%:p:h')
call s:command_abbrev('vp', 'vs%:p:h')
call s:command_abbrev('rm', '!rm')
call s:command_abbrev('mv', '!mv')
call s:command_abbrev('mkd', '!mkdir')
call s:command_abbrev('mkdir', '!mkdir')
call s:command_abbrev('touch', '!touch')

abbrev ture  true
abbrev Ture  True
abbrev flase false
abbrev fasle false
abbrev Flase False
abbrev Fasle False

runtime ftplugin/man.vim
call s:command_abbrev('man', 'Man')
" }}}

""" Keymaps {{{1
let g:mapleader = ' '
let g:maplocalleader = ' '

nnoremap <expr> j v:count ? 'j' : 'gj'
nnoremap <expr> k v:count ? 'k' : 'gk'
xnoremap <expr> j v:count ? 'j' : 'gj'
xnoremap <expr> k v:count ? 'k' : 'gk'

nnoremap <expr> $      &wrap ? 'g$'      : '$'
nnoremap <expr> 0      &wrap ? 'g0'      : '0'
xnoremap <expr> ^      &wrap ? 'g^'      : '^'
xnoremap <expr> <Home> &wrap ? 'g<Home>' : '<Home>'
xnoremap <expr> <End>  &wrap ? 'g<End>'  : '<End>'

nnoremap <silent> ]b :exec v:count1 . 'bn'<CR>
nnoremap <silent> [b :exec v:count1 . 'bp'<CR>

" Tabpages
" param: tab_action tab switch command 'tabnext'|'tabprev'
" param: a:1 default_count number? default to v:count
" return: 0
function! TabSwitch(tab_action, ...) abort
  let cnt = get(a:, 1, v:count)
  let num_tabs = tabpagenr('$')
  if num_tabs >= cnt
    exe printf('silent! %s %s', a:tab_action, cnt == 0 ? '' : string(cnt))
    return
  endif
  tablast
  for _ in range(cnt - num_tabs)
    tabnew
  endfor
endfunction

nnoremap <silent> gt :<C-u>call TabSwitch('tabnext')<CR>
nnoremap <silent> gT :<C-u>call TabSwitch('tabprev')<CR>
nnoremap <silent> gy :<C-u>call TabSwitch('tabprev')<CR>

for i in range(1, 9)
  exe printf("nnoremap <silent> <Leader>%d
        \ :<C-u>call TabSwitch('tabnext', %d)<CR>", i, i)
endfor

inoremap <C-L> <Esc>[szg`]a
inoremap <C-l> <C-g>u<Esc>[s1z=`]a<C-G>u

xmap a" 2i"
xmap a' 2i'
xmap a` 2i`
omap a" 2i"
omap a' 2i'
omap a` 2i`

" Return key seq to jump to the first line in paragraph
" return: 0
function! s:paragraph_first_line() abort
  let chunk_size = 10
  let init_linenr = line('.')
  let linenr = init_linenr
  let cnt = v:count1

  " If current line is the first line of paragraph, move one line
  " upwards first to goto the first line of previous paragraph
  if linenr >= 2
    let lines = getbufline(bufname(), linenr - 1, linenr)
    if lines[0] =~# '^$' && lines[1] =~# '\S'
      let linenr -= 1
    endif
  endif

  while linenr >= 1
    let chunk = getbufline(
          \ bufname(),
          \ max([0, linenr - chunk_size - 1]),
          \ linenr - 1,
          \ )
    let i = 0
    for line in reverse(chunk)
      let i += 1
      let current_linenr = linenr - i
      if line =~# '^$'
        let cnt -= 1
        if cnt <= 0
          return "m'" . (init_linenr - current_linenr - 1) . 'k'
        endif
      elseif current_linenr <= 1
        return "m'gg"
      endif
    endfor
    let linenr -= chunk_size
  endwhile
endfunction

" Return key seq to jump to the last line in paragraph
" return: 0
function! s:paragraph_last_line() abort
  let chunk_size = 10
  let init_linenr = line('.')
  let linenr = init_linenr
  let buf_line_count = line('$')
  let cnt = v:count1

  " If current line is the last line of paragraph, move one line
  " downwards first to goto the last line of next paragraph
  if buf_line_count - linenr >= 1
    let lines = getbufline(bufname(), linenr, linenr + 1)
    if lines[0] =~# '\S' && lines[1] =~# '^$'
      let linenr += 1
    end
  end

  while linenr <= buf_line_count
    let chunk = getbufline(
          \ bufname(),
          \ linenr + 1,
          \ linenr + chunk_size + 1,
          \ )
    let i = 0
    for line in chunk
      let i += 1
      let current_linenr = linenr + i
      if line =~# '^$'
        let cnt -= 1
        if cnt <= 0
          return "m'" . (current_linenr - init_linenr - 1) . 'j'
        endif
      elseif current_linenr >= buf_line_count
        return "m'G"
      endif
    endfor
    let linenr += chunk_size
  endwhile
endfunction

" Use 'g{' or 'g}' to move to the first/last line of a paragraph
nmap <silent><expr> g{ <SID>paragraph_first_line()
nmap <silent><expr> g} <SID>paragraph_last_line()
xmap <silent><expr> g{ <SID>paragraph_first_line()
xmap <silent><expr> g} <SID>paragraph_last_line()
omap <silent>       g{ :silent! normal Vg{<CR>
omap <silent>       g} :silent! normal Vg}<CR>

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

  exe map . '<expr> <Esc>+ v:count ? "<C-w>+" : "2<C-w>+"'
  exe map . '<expr> <Esc>- v:count ? "<C-w>-" : "2<C-w>-"'
  if has('patch-8.1.1140')
    exe map . '<expr> <Esc>> (v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w><" : "<C-w>>")'
    exe map . '<expr> <Esc>< (v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w>>" : "<C-w><")'
    exe map . '<expr> <Esc>. (v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w><" : "<C-w>>")'
    exe map . '<expr> <Esc>, (v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w>>" : "<C-w><")'
    exe map . '<expr> <C-w>> (v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w><" : "<C-w>>")'
    exe map . '<expr> <C-w>< (v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w>>" : "<C-w><")'
    exe map . '<expr> <C-w>. (v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w><" : "<C-w>>")'
    exe map . '<expr> <C-w>, (v:count ? "" : 4) . (winnr() == winnr("l") ? "<C-w>>" : "<C-w><")'
  else
    exe map . '<expr> <Esc>> (v:count ? "" : 4) . "<C-w>>"'
    exe map . '<expr> <Esc>< (v:count ? "" : 4) . "<C-w><"'
    exe map . '<expr> <Esc>. (v:count ? "" : 4) . "<C-w>>"'
    exe map . '<expr> <Esc>, (v:count ? "" : 4) . "<C-w><"'
    exe map . '<expr> <C-w>> (v:count ? "" : 4) . "<C-w>>"'
    exe map . '<expr> <C-w>< (v:count ? "" : 4) . "<C-w><"'
    exe map . '<expr> <C-w>. (v:count ? "" : 4) . "<C-w>>"'
    exe map . '<expr> <C-w>, (v:count ? "" : 4) . "<C-w><"'
  endif
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
cnoremap <C-_> <C-f>
cnoremap <C-g> <C-\><C-n>
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
  return s:match_nonempty(str[colnr - 1:], '^\s*\w*', '^\s*[^ \t0-9A-Za-z_]*')
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
        \ '[^ \t0-9A-Za-z_]*\s*$')
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
  return s:end_of_line() ? "\<C-g>u\<Del>" : "\<C-g>u\<C-o>D\<Right>"
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
" Check if an event or a list of events are supported
" param: events string|string[] event or list of events
" return: 0/1
function! s:supportevents(events) abort
  if type(a:events) == v:t_string
    return exists('##' . a:events)
  endif
  if type(a:events) == v:t_list
    for event in a:events
      if !exists('##' . event)
        return 0
      endif
    endfor
    return 1
  endif
  return 0
endfunction

if s:supportevents(['BufLeave', 'WinLeave', 'FocusLost'])
  augroup AutoSave
    au!
    if has('patch-8.1113')
      au BufLeave,WinLeave,FocusLost * ++nested if &bt ==# "" |
            \ silent! up |
            \ endif
    else
      au BufLeave,WinLeave,FocusLost * if &bt ==# "" | silent! up | endif
    endif
  augroup END
endif

if s:supportevents('QuickFixCmdPost') && exists('*timer_start')
  function! s:defer_open_qflist(type) abort
    if expand(a:type) =~# '^l'
      call timer_start(0, {-> execute('bel lwindow')})
    else
      call timer_start(0, {-> execute('bot cwindow')})
    endif
  endfunction

  augroup QuickFixAutoOpen
    au!
    au QuickFixCmdPost * if len(getqflist()) > 1 |
          \ call s:defer_open_qflist(expand('<amatch>')) |
          \ endif
  augroup END
endif

if s:supportevents('VimResized')
  augroup EqualWinSize
    au!
    au VimResized * wincmd =
  augroup END
endif

if s:supportevents('OptionSet')
  augroup TextwidthRelativeColorcolumn
    au!
    au OptionSet textwidth if v:option_new | setlocal cc=+1 | endif
  augroup END
endif

if s:supportevents('BufReadPost')
  augroup LastPosJmp
    au!
    au BufReadPost * if &ft !=# 'gitcommit' && &ft !=# 'gitrebase' |
          \ exe 'silent! normal! g`"zvzz' |
          \ endif
  augroup END
endif

" Jump to last accessed window on closing the current one
if s:supportevents('WinClosed')
  augroup WinCloseJmp
    au!
    au WinClosed * ++nested if expand('<amatch>') == win_getid() |
          \ wincmd p |
          \ endif
  augroup END
endif

if s:supportevents([
      \ 'BufReadPost',
      \ 'BufWinEnter',
      \ 'WinEnter',
      \ 'FileChangedShellPost'
      \ ])
  " Compute project directory for given path.
  " param: fpath string
  " param: a:1 patterns string[]? root patterns
  " return: string returns path of project root directory if found,
  "         else returns empty string
  function! s:proj_dir(fpath, ...) abort
    if a:fpath == ''
      return ''
    endif
    let patterns = get(a:, 1, [
        \ '.git/',
        \ '.svn/',
        \ '.bzr/',
        \ '.hg/',
        \ '.project/',
        \ '.pro',
        \ '.sln',
        \ '.vcxproj',
        \ 'Makefile',
        \ 'makefile',
        \ 'MAKEFILE',
        \ '.gitignore',
        \ '.editorconfig'])
    let dirpath = fnamemodify(a:fpath, ':p:h') . ';'
    for pattern in patterns
      if pattern =~# '/$'
        let target_path = finddir(pattern, dirpath)
        if target_path !=# ''
          return fnamemodify(target_path, ':p:h:h')
        endif
      else
        let target_path = findfile(pattern, dirpath)
        if target_path !=# ''
          return fnamemodify(target_path, ':p:h')
        endif
      endif
    endfor
    return ''
  endfunction

  " Change current working directory to project root directory.
  " param: fpath string path to current file
  function! s:autocwd(fpath) abort
    let fpath = fnamemodify(a:fpath, ':p')
    if fpath ==# '' || !isdirectory(fpath) && !filereadable(fpath)
      return
    endif
    let proj_dir = s:proj_dir(fpath)
    if proj_dir !=# ''
      exe 'lcd ' . proj_dir
      return
    endif
    let dirname = fnamemodify(fpath, ':p:h')
    if isdirectory(dirname)
      exe 'lcd ' . dirname
    endif
  endfunction

  augroup AutoCwd
    au!
    autocmd BufReadPost,BufWinEnter,FileChangedShellPost *
          \ if &bt == '' && &ma | call <SID>autocwd(expand('<afile>')) | endif
  augroup END
endif

if s:supportevents(['BufWinEnter', 'BufUnload'])
  " Update folds for given buffer
  " param: bufnr integer
  function! s:update_folds_once(bufnr)
    if !getbufvar(a:bufnr, 'foldupdated', 0) && bufexists(a:bufnr)
      call setbufvar(a:bufnr, 'foldupdated', 1)
      exe 'normal! zx'
    endif
  endfunction

  augroup UpdateFolds
    au!
    au BufWinEnter * :call s:update_folds_once(expand('<abuf>'))
    au BufUnload   * :call setbufvar(expand('<abuf>'), 'foldupdated', 0)
  augroup END
endif

" Restore and switch background from viminfo file,
" for this autocmd to work properly, 'viminfo' option must contain '!'
if ($COLORTERM ==# 'truecolor' || has('gui_running'))
      \ && s:supportevents(['VimEnter', 'OptionSet', 'ColorScheme'])

  " Restore &background and colorscheme from viminfo file
  function! s:theme_restore() abort
    let BACKGROUND = get(g:, 'BACKGROUND', '')
    if BACKGROUND !=# '' && BACKGROUND !=# &background
      let &background=BACKGROUND
    endif
    let colors_name = get(g:, 'colors_name', '')
    let COLORSNAME = get(g:, 'COLORSNAME', '')
    if colors_name ==# '' || COLORSNAME != colors_name
      exe 'silent! colorscheme ' . COLORSNAME
      call s:theme_fix_hlspell()
    endif
  endfunction

  " Save current &background and colorscheme to global variables
  function! s:theme_save() abort
    let g:BACKGROUND = &background
    let g:COLORSNAME = get(g:, 'colors_name', '')
    silent! wviminfo
  endfunction

  " Override hl-SpellBad, hl-SpellCap, hl-SpellRare, and hl-SpellLocalA
  function! s:theme_fix_hlspell() abort
    hi clear SpellBad
    hi! SpellBad term=underline gui=underline
    hi! link SpellCap SpellBad
    hi! link SpellRare SpellBad
    hi! link SpellLocal SpellBad
  endfunction

  augroup ThemeSwitch
    au!
    au VimEnter    * ++once :call s:theme_restore()
    au ColorScheme *        :call s:theme_save()
    au ColorScheme *        :call s:theme_fix_hlspell()
  augroup END
endif

" Clear strange escape sequence shown when using alt keys to navigate away
" from tmux panes running vim
if s:supportevents('FocusLost')
  augroup FocusLostClearScreen
    au!
    au FocusLost * :silent! redraw!
  augroup END
endif

if s:supportevents(['CursorMoved', 'ModeChanged'])
  augroup FixVirtualEditCursorPos
    au!
    " Record cursor position in visual mode if virtualedit is set and
    " contains 'all' or 'block'
    au CursorMoved * if &ve =~# 'all' |
          \ let w:ve_cursor = getcurpos() |
          \ endif
    " Keep cursor position after entering normal mode from visual mode with
    " virtualedit enabled
    au ModeChanged [vV\x16]*:n if &ve =~# 'all' && exists('w:ve_cursor') |
          \ call setpos('.', w:ve_cursor) |
          \ endif
  augroup END
endif
" }}}1

""" Plugin Settings {{{1
" Netrw {{{2
let g:netrw_banner = 0
let g:netrw_cursor = 5
let g:netrw_fastbrowse = 0
let g:netrw_keepdir = 0
let g:netrw_list_hide = netrw_gitignore#Hide()
let g:netrw_liststyle = 1
let g:netrw_localcopydircmd = 'cp -r'

" return: string
function s:netrw_ctrl_o() abort
  let jumplist = getjumplist()
  let prevloc_idx = jumplist[1] - 1
  if prevloc_idx < 0 || prevloc_idx >= len(jumplist[0])
    return "\<Ignore>"
  endif
  let prevloc = jumplist[0][prevloc_idx]
  if prevloc.bufnr != bufnr('%')
    return "\<Ignore>"
  end
  return "\<C-o>"
endfunction

" return: string
function s:netrw_ctrl_i() abort
  let jumplist = getjumplist()
  let newloc_idx = jumplist[1] + 1
  if newloc_idx >= len(jumplist[0])
    return "\<Ignore>"
  endif
  let newloc = jumplist[0][newloc_idx]
  if newloc.bufnr != bufnr('%')
    return "\<Ignore>"
  end
  return "\<C-i>"
endfunction

if s:supportevents('FileType')
  augroup NetrwSettings
    au!
    au FileType netrw setlocal
          \ bufhidden=wipe
          \ buftype=nofile
          \ nobuflisted
          \ nolist
          \ nonumber
          \ norelativenumber
          \ nospell
          \ signcolumn=no
          \ | :nnoremap <buffer><expr> <C-o> <SID>netrw_ctrl_o()
          \ | :nnoremap <buffer><expr> <C-i> <SID>netrw_ctrl_i()
  augroup END
endif
" }}}2

" FZF {{{2
let g:fzf_layout = {
      \ 'window': {
        \ 'width': 0.7,
        \ 'height': 0.7,
        \ 'pos': 'center',
        \ }
      \ }
let $FZF_DEFAULT_OPTS .= ' --border=sharp --margin=0 --padding=0'

" Some keymaps
nnoremap <silent> <Leader>ff :FZF<CR>
nnoremap <silent> <Leader>.  :FZF<CR>

" Use fzf as file explorer
" runtime plugin/fzf.vim
" if exists('*timer_start') && exists(':FZF') == 2
"   let g:loaded_netrw       = 1
"   let g:loaded_netrwPlugin = 1
"
"   let g:buf_created = {}
"
"   " param: dir string
"   function! s:fzf_edit_dir(dir) abort
"     if !isdirectory(a:dir) || exists(':FZF') != 2
"       return
"     endif
"     " Switch to alternate buffer if current buffer is a directory
"     if isdirectory(bufname('%'))
"       let &bufhidden = 'wipe'
"       let buf0 = bufnr(0)
"       let bufcur = bufnr('%')
"       if buf0 == -1 || buf0 == bufcur || get(g:buf_created, bufcur, 0)
"         enew
"       else
"         buffer #
"       endif
"     endif
"     " Open fzf window
"     call timer_start(0, {-> execute('FZF ' . fnameescape(a:dir))})
"     call timer_start(0, {-> execute('call feedkeys("\<Left>", "nt")')})
"   endfunction
"
"   " param: buf integer
"   function! s:fzf_rm_defer_check_buf(buf) abort
"     if !bufexists(a:buf) && get(g:buf_created, a:buf, 0)
"       call remove(g:buf_created, a:buf)
"     endif
"   endfunction
"
"   " param: buf integer
"   function! s:fzf_rm_buf_record(buf) abort
"     call timer_start(0, {-> s:fzf_rm_defer_check_buf(a:buf)})
"   endfunction
"
"   augroup FzfFileExploer
"     au!
"     au BufEnter * :call s:fzf_edit_dir(expand('<amatch>'))
"           \ | let g:buf_created[expand('<abuf>')] = 1
"     au BufWipeout * :call s:fzf_rm_buf_record(expand('<abuf>'))
"   augroup END
" endif
" }}}2
" }}}1

""" Misc {{{1
" Terminal Settings {{{2
if s:supportevents('TerminalWinOpen')
  " return: reltime() converted to ms
  function! s:reltime_ms() abort
    let t = reltime()
    return t[0] * 1000 + t[1] / 1000000
  endfunction

  " param: a:1 whether to store a timestamp in the terminal buffer
  " return: 0/1
  function! s:shall_esc(...) abort
    if &buftype !~# 'terminal'
      return 0
    endif
    if get(a:, 1, 0)
      let b:t_esc = s:reltime_ms()
    endif
    let pid = job_info(term_getjob(bufnr())).process
    let command = trim(system('ps h -o comm -g ' . pid . ' | tail -n1'))
    if v:shell_error
      return 1
    endif
    return match(command, '\v^((ba|da|fi|z)?sh|less|gawk|i?python3?)$') >= 0
  endfunction

  tnoremap <Esc>W  <C-\><C-n><C-w>Wi
  tnoremap <Esc>H  <C-\><C-n><C-w>Hi
  tnoremap <Esc>J  <C-\><C-n><C-w>Ji
  tnoremap <Esc>K  <C-\><C-n><C-w>Ki
  tnoremap <Esc>L  <C-\><C-n><C-w>Li
  tnoremap <Esc>=  <C-\><C-n><C-w>=i
  tnoremap <Esc>_  <C-\><C-n><C-w>_i
  tnoremap <Esc>\| <C-\><C-n><C-w>\|i
  if has('patch-8.1.1140')
    tnoremap <expr> <Esc>> '<C-\><C-n><C-w>4' . (winnr() == winnr('l') ? '<' : '>') . 'i'
    tnoremap <expr> <Esc>< '<C-\><C-n><C-w>4' . (winnr() == winnr('l') ? '>' : '<') . 'i'
    tnoremap <expr> <Esc>. '<C-\><C-n><C-w>4' . (winnr() == winnr('l') ? '<' : '>') . 'i'
    tnoremap <expr> <Esc>, '<C-\><C-n><C-w>4' . (winnr() == winnr('l') ? '>' : '<') . 'i'
  else
    tnoremap <Esc>> '<C-\><C-n><C-w>4>i'
    tnoremap <Esc>< '<C-\><C-n><C-w>4<i'
    tnoremap <Esc>. '<C-\><C-n><C-w>4>i'
    tnoremap <Esc>, '<C-\><C-n><C-w>4<i'
  endif
  tnoremap <Esc>+  <C-\><C-n><C-w>2+i
  tnoremap <Esc>-  <C-\><C-n><C-w>2-i
  tnoremap <Esc>r  <C-\><C-n><C-w>ri
  tnoremap <Esc>R  <C-\><C-n><C-w>Ri
  tnoremap <Esc>x  <C-\><C-n><C-w>x
  tnoremap <Esc>p  <C-\><C-n><C-w>p
  tnoremap <Esc>c  <C-\><C-n><C-w>c
  tnoremap <Esc>o  <C-\><C-n><C-w>o
  tnoremap <Esc>w  <C-\><C-n><C-w>w
  tnoremap <Esc>h  <C-\><C-n><C-w>h
  tnoremap <Esc>j  <C-\><C-n><C-w>j
  tnoremap <Esc>k  <C-\><C-n><C-w>k
  tnoremap <Esc>l  <C-\><C-n><C-w>l

  augroup TermOptions
    au!
    au TerminalWinOpen * setlocal nonu nornu scl=no bh=hide so=0 siso=0 |
          \ nnoremap <buffer> o i |
          \ nnoremap <nowait><expr><buffer> <Esc> <SID>shall_esc()
            \ && exists('b:t_esc')
            \ && <SID>reltime_ms() - b:t_esc <= &tm ? 'i' : '<Esc>' |
          \ tnoremap <nowait><expr><buffer> <Esc>
            \ <SID>shall_esc(1) ? '<C-\><C-n>' : '<Esc>' |
          \ startinsert
  augroup END
endif
" }}}2

" Navigate tmux panes using vim-style motions {{{2
if executable('tmux') && $TMUX !=# '' && $TMUX_PANE !=# '' && has('patch-8.1.1140')
  " return: string tmux socket path
  function! s:tmux_get_socket() abort
    return get(split($TMUX, ','), 0, '')
  endfunction

  " param: command string tmux command to execute
  " return: string tmux command output
  function! s:tmux_exec(command) abort
    let command = printf('tmux -S %s %s', s:tmux_get_socket(), a:command)
    return system(command)
  endfunction

  " Get tmux option value in current pane
  " param: opt string tmux pane option
  " return: string tmux pane option value
  function! s:tmux_get_pane_opt(opt) abort
    return substitute(s:tmux_exec(printf(
            \ "display-message -pt %s '#{%s}'",
            \ $TMUX_PANE,
            \ escape(a:opt, "'\\"))
          \ ), '\n.*', '', '')
  endfunction

  " Set tmux option value in current pane
  " param: opt string tmux pane option
  " param: val string tmux pane option value
  " return: 0
  function! s:tmux_set_pane_opt(opt, val) abort
    call s:tmux_exec(printf(
            \ "set -pt %s %s '%s'",
            \ $TMUX_PANE,
            \ a:opt,
            \ escape(a:val, "'\\")
          \ ))
  endfunction

  " Unset a tmux pane option
  " param: opt string tmux pane option
  " return: 0
  function! s:tmux_unset_pane_opt(opt) abort
    call s:tmux_exec(printf(
            \ "set -put %s '%s'",
            \ $TMUX_PANE,
            \ escape(a:opt, "'\\")
          \ ))
  endfunction

  " return: 0/1
  function! s:tmux_is_zoomed() abort
    return s:tmux_get_pane_opt('window_zoomed_flag') ==# '1'
  endfunction

  let s:tmux_pane_position_map = {
        \ 'h': 'left',
        \ 'j': 'bottom',
        \ 'k': 'top',
        \ 'l': 'right',
        \ }

  " param: direction string
  " return: 0/1
  function! s:tmux_at_border(direction) abort
    return s:tmux_get_pane_opt(
          \ 'pane_at_' . s:tmux_pane_position_map[a:direction]) ==# '1'
  endfunction

  " param: direction string
  " return: 0/1
  function! s:tmux_should_move(direction) abort
    return ! s:tmux_is_zoomed() && ! s:tmux_at_border(a:direction)
  endfunction

  let s:tmux_direction_map = {
        \ 'h': 'L',
        \ 'j': 'D',
        \ 'k': 'U',
        \ 'l': 'R',
        \ }

  " param: direction string
  " param: cnt integer? default to 1
  function! s:tmux_navigate(direction, ...) abort
    let cnt = get(a:, 1, 1)
    for i in range(cnt)
      call s:tmux_exec(printf("select-pane -t '%s' -%s",
            \ $TMUX_PANE, s:tmux_direction_map[a:direction]))
    endfor
  endfunction

  " param: direction string
  " return: 0/1
  function! s:vim_at_border(direction) abort
    return winnr() == winnr(a:direction)
  endfunction

  " return: 0/1
  function! s:vim_in_popup_win() abort
    return win_gettype() ==# 'popup'
  endfunction

  function! s:vim_has_only_win() abort
    return winnr('$') <= 1 && tabpagenr('$') <= 1
  endfunction

  function s:vim_tabpage_has_only_win() abort
    return winnr('$') <= 1
  endfunction

  " param: direction integer
  " param: cnt integer? default to 1
  function! s:vim_navigate(direction, ...) abort
    let cnt = get(a:, 1, 1)
    exe cnt . 'wincmd ' . a:direction
  endfunction

  " param: direction integer
  " param: cnt integer? default to 1
  function! s:navigate(direction, ...) abort
    let cnt = get(a:, 1, 1)
    if (s:vim_at_border(a:direction) || s:vim_in_popup_win())
          \ && s:tmux_should_move(a:direction)
      call s:tmux_navigate(a:direction, cnt)
    else
      call s:vim_navigate(a:direction, cnt)
    endif
  endfunction

  nnoremap <silent> <Esc>h :<C-u>call <SID>navigate('h', v:count1)<CR>
  nnoremap <silent> <Esc>j :<C-u>call <SID>navigate('j', v:count1)<CR>
  nnoremap <silent> <Esc>k :<C-u>call <SID>navigate('k', v:count1)<CR>
  nnoremap <silent> <Esc>l :<C-u>call <SID>navigate('l', v:count1)<CR>

  xnoremap <silent> <Esc>h :<C-u>call <SID>navigate('h', v:count1)<CR>
  xnoremap <silent> <Esc>j :<C-u>call <SID>navigate('j', v:count1)<CR>
  xnoremap <silent> <Esc>k :<C-u>call <SID>navigate('k', v:count1)<CR>
  xnoremap <silent> <Esc>l :<C-u>call <SID>navigate('l', v:count1)<CR>

  tnoremap <silent> <Esc>h <C-\><C-n>:<C-u>call <SID>navigate('h', v:count1)<CR>
  tnoremap <silent> <Esc>j <C-\><C-n>:<C-u>call <SID>navigate('j', v:count1)<CR>
  tnoremap <silent> <Esc>k <C-\><C-n>:<C-u>call <SID>navigate('k', v:count1)<CR>
  tnoremap <silent> <Esc>l <C-\><C-n>:<C-u>call <SID>navigate('l', v:count1)<CR>

  " return: 0/1
  function! s:tmux_mapkey_default_condition() abort
    return ! s:tmux_is_zoomed() && s:vim_tabpage_has_only_win()
  endfunction
  let TmuxMapKeyDefaultConditionRef = function(
        \ 's:tmux_mapkey_default_condition')

  " return: 0/1
  function! s:tmux_mapkey_close_win_condition() abort
    return ! s:tmux_is_zoomed() && s:vim_has_only_win()
  endfunction
  let TmuxMapkeyCloseWinConditionRef = function(
        \ 's:tmux_mapkey_close_win_condition')

  " return: 0/1
  function! s:tmux_mapkey_resize_pane_horiz_condition() abort
    return ! s:tmux_is_zoomed() && (s:vim_at_border('l') &&
          \ (s:vim_at_border('h') || ! s:tmux_at_border('l')))
  endfunction
  let TmuxMapkeyResizePaneHorizConditionRef = function(
        \ 's:tmux_mapkey_resize_pane_horiz_condition')

  " return: 0/1
  function! s:tmux_mapkey_resize_pane_vert_condition() abort
    return ! s:tmux_is_zoomed() && (s:vim_at_border('j') &&
          \ (s:vim_at_border('k') || ! s:tmux_at_border('j')))
  endfunction
  let TmuxMapkeyResizePaneVertConditionRef = function(
        \ 's:tmux_mapkey_resize_pane_vert_condition')

  " param: command string
  " param: key_fallback string
  " param: condition? fun(): boolean
  " return: string (rhs)
  function! s:tmux_mapkey_fallback(command, key_fallback, ...) abort
    let Condition = get(a:, 1, g:TmuxMapKeyDefaultConditionRef)
    if Condition()
      call s:tmux_exec(a:command)
      return "\<Ignore>"
    endif
    return a:key_fallback
  endfunction

  nnoremap <expr><silent> <Esc>p <SID>tmux_mapkey_fallback('last-pane', '<C-w>p')
  nnoremap <expr><silent> <Esc>R <SID>tmux_mapkey_fallback('swap-pane -U', '<C-w>R')
  nnoremap <expr><silent> <Esc>r <SID>tmux_mapkey_fallback('swap-pane -D', '<C-w>r')
  nnoremap <expr><silent> <Esc>o <SID>tmux_mapkey_fallback("confirm 'kill-pane -a'", '<C-w>o')
  nnoremap <expr><silent> <Esc>= <SID>tmux_mapkey_fallback("confirm 'select-layout tiled'", '<C-w>=')
  nnoremap <expr><silent> <Esc>c <SID>tmux_mapkey_fallback('confirm kill-pane', '<C-w>c', TmuxMapkeyCloseWinConditionRef)
  nnoremap <expr><silent> <Esc>< <SID>tmux_mapkey_fallback('resize-pane -L 4', (v:count ? '' : 4) . (winnr() == winnr('l') ? '<C-w>>' : '<C-w><'), TmuxMapkeyResizePaneHorizConditionRef)
  nnoremap <expr><silent> <Esc>> <SID>tmux_mapkey_fallback('resize-pane -R 4', (v:count ? '' : 4) . (winnr() == winnr('l') ? '<C-w><' : '<C-w>>'), TmuxMapkeyResizePaneHorizConditionRef)
  nnoremap <expr><silent> <Esc>, <SID>tmux_mapkey_fallback('resize-pane -L 4', (v:count ? '' : 4) . (winnr() == winnr('l') ? '<C-w>>' : '<C-w><'), TmuxMapkeyResizePaneHorizConditionRef)
  nnoremap <expr><silent> <Esc>. <SID>tmux_mapkey_fallback('resize-pane -R 4', (v:count ? '' : 4) . (winnr() == winnr('l') ? '<C-w><' : '<C-w>>'), TmuxMapkeyResizePaneHorizConditionRef)
  nnoremap <expr><silent> <Esc>- <SID>tmux_mapkey_fallback("run \"tmux resize-pane -y $(($(tmux display -p '#{pane_height}') - 2))\"", v:count ? '<C-w>-' : '2<C-w>-', TmuxMapkeyResizePaneVertConditionRef)
  nnoremap <expr><silent> <Esc>+ <SID>tmux_mapkey_fallback("run \"tmux resize-pane -y $(($(tmux display -p '#{pane_height}') + 2))\"", v:count ? '<C-w>+' : '2<C-w>+', TmuxMapkeyResizePaneVertConditionRef)

  xnoremap <expr><silent> <Esc>p <SID>tmux_mapkey_fallback('last-pane', '<C-w>p')
  xnoremap <expr><silent> <Esc>R <SID>tmux_mapkey_fallback('swap-pane -U', '<C-w>R')
  xnoremap <expr><silent> <Esc>r <SID>tmux_mapkey_fallback('swap-pane -D', '<C-w>r')
  xnoremap <expr><silent> <Esc>o <SID>tmux_mapkey_fallback("confirm 'kill-pane -a'", '<C-w>o')
  xnoremap <expr><silent> <Esc>= <SID>tmux_mapkey_fallback("confirm 'select-layout tiled'", '<C-w>=')
  xnoremap <expr><silent> <Esc>c <SID>tmux_mapkey_fallback('confirm kill-pane', '<C-w>c', TmuxMapkeyCloseWinConditionRef)
  xnoremap <expr><silent> <Esc>< <SID>tmux_mapkey_fallback('resize-pane -L 4', (v:count ? '' : 4) . (winnr() == winnr('l') ? '<C-w>>' : '<C-w><'), TmuxMapkeyResizePaneHorizConditionRef)
  xnoremap <expr><silent> <Esc>> <SID>tmux_mapkey_fallback('resize-pane -R 4', (v:count ? '' : 4) . (winnr() == winnr('l') ? '<C-w><' : '<C-w>>'), TmuxMapkeyResizePaneHorizConditionRef)
  xnoremap <expr><silent> <Esc>, <SID>tmux_mapkey_fallback('resize-pane -L 4', (v:count ? '' : 4) . (winnr() == winnr('l') ? '<C-w>>' : '<C-w><'), TmuxMapkeyResizePaneHorizConditionRef)
  xnoremap <expr><silent> <Esc>. <SID>tmux_mapkey_fallback('resize-pane -R 4', (v:count ? '' : 4) . (winnr() == winnr('l') ? '<C-w><' : '<C-w>>'), TmuxMapkeyResizePaneHorizConditionRef)
  xnoremap <expr><silent> <Esc>- <SID>tmux_mapkey_fallback("run \"tmux resize-pane -y $(($(tmux display -p '#{pane_height}') - 2))\"", v:count ? '<C-w>-' : '2<C-w>-', TmuxMapkeyResizePaneVertConditionRef)
  xnoremap <expr><silent> <Esc>+ <SID>tmux_mapkey_fallback("run \"tmux resize-pane -y $(($(tmux display -p '#{pane_height}') + 2))\"", v:count ? '<C-w>+' : '2<C-w>+', TmuxMapkeyResizePaneVertConditionRef)

  tnoremap <expr><silent> <Esc>p '<C-\><C-n>' . <SID>tmux_mapkey_fallback('last-pane', '<C-w>p')
  tnoremap <expr><silent> <Esc>R '<C-\><C-n>' . <SID>tmux_mapkey_fallback('swap-pane -U', '<C-w>Ri')
  tnoremap <expr><silent> <Esc>r '<C-\><C-n>' . <SID>tmux_mapkey_fallback('swap-pane -D', '<C-w>ri')
  tnoremap <expr><silent> <Esc>o '<C-\><C-n>' . <SID>tmux_mapkey_fallback("confirm 'kill-pane -a'", '<C-w>oi')
  tnoremap <expr><silent> <Esc>= '<C-\><C-n>' . <SID>tmux_mapkey_fallback("confirm 'select-layout tiled'", '<C-w>=i')
  tnoremap <expr><silent> <Esc>c '<C-\><C-n>' . <SID>tmux_mapkey_fallback('confirm kill-pane', '<C-w>c', TmuxMapkeyCloseWinConditionRef)
  tnoremap <expr><silent> <Esc>< '<C-\><C-n>' . <SID>tmux_mapkey_fallback('resize-pane -L 4', '4<C-w>' . (winnr() == winnr('l') ? '>' : '<') . 'i', TmuxMapkeyResizePaneHorizConditionRef)
  tnoremap <expr><silent> <Esc>> '<C-\><C-n>' . <SID>tmux_mapkey_fallback('resize-pane -R 4', '4<C-w>' . (winnr() == winnr('l') ? '<' : '>') . 'i', TmuxMapkeyResizePaneHorizConditionRef)
  tnoremap <expr><silent> <Esc>, '<C-\><C-n>' . <SID>tmux_mapkey_fallback('resize-pane -L 4', '4<C-w>' . (winnr() == winnr('l') ? '>' : '<') . 'i', TmuxMapkeyResizePaneHorizConditionRef)
  tnoremap <expr><silent> <Esc>. '<C-\><C-n>' . <SID>tmux_mapkey_fallback('resize-pane -R 4', '4<C-w>' . (winnr() == winnr('l') ? '<' : '>') . 'i', TmuxMapkeyResizePaneHorizConditionRef)
  tnoremap <expr><silent> <Esc>- '<C-\><C-n>' . <SID>tmux_mapkey_fallback("run \"tmux resize-pane -y $(($(tmux display -p '#{pane_height}') - 2))\"", '2<C-w>-i', TmuxMapkeyResizePaneVertConditionRef)
  tnoremap <expr><silent> <Esc>+ '<C-\><C-n>' . <SID>tmux_mapkey_fallback("run \"tmux resize-pane -y $(($(tmux display -p '#{pane_height}') + 2))\"", '2<C-w>+i', TmuxMapkeyResizePaneVertConditionRef)

  " Use a unified keymap `<C-space>[` to escape from vim terminal mode or enter
  " tmux visual mode
  tnoremap                <C-@>[ <C-\><C-n>
  nnoremap <expr><silent> <C-@>[ <SID>tmux_exec('copy-mode')
  vnoremap <expr><silent> <C-@>[ <SID>tmux_exec('copy-mode')
  onoremap <expr><silent> <C-@>[ <SID>tmux_exec('copy-mode')
  inoremap <expr><silent> <C-@>[ <SID>tmux_exec('copy-mode')
  cnoremap <expr><silent> <C-@>[ <SID>tmux_exec('copy-mode')
  lnoremap <expr><silent> <C-@>[ <SID>tmux_exec('copy-mode')

  " Set @is_vim and register relevant autocmds callbacks if not already
  " in a vim/nvim session
  if s:tmux_get_pane_opt('@is_vim') ==# ''
    call s:tmux_set_pane_opt('@is_vim', 'yes')
    if s:supportevents(['VimResume', 'VimLeave', 'VimSuspend'])
      augroup TmuxNavSetIsVim
        au!
        au VimResume           * :call s:tmux_set_pane_opt('@is_vim', 'yes')
        au VimLeave,VimSuspend * :call s:tmux_unset_pane_opt('@is_vim')
      augroup END
    endif
  endif
endif
" }}}2

" Qflist / quickfix list settings {{{2
if s:supportevents('FileType')
  augroup QfSettings
    au!
    au FileType qf setlocal nobl nornu scl=no |
          \ nnoremap <buffer> <Tab> <CR>zz<C-w>p |
          \ nnoremap <buffer> <C-j> j<CR>zz<C-w>p |
          \ nnoremap <buffer> <C-k> k<CR>zz<C-w>p |
          \ nnoremap <buffer> <C-n> j<CR>zz<C-w>p |
          \ nnoremap <buffer> <C-p> k<CR>zz<C-w>p
  augroup END
endif
" }}}2

" Workaround to prevent <Esc> lag cause by Meta keymaps
noremap  <nowait> <Esc> <Esc>
noremap! <nowait> <Esc> <C-\><C-n>
tnoremap <nowait> <Esc> <Esc>
" }}}1

" vim:tw=79:ts=2:sts=2:sw=2:et:fdm=marker:ft=vim:norl:
