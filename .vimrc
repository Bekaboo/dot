""" Options {{{1
silent! set notimeout
silent! set hidden
silent! set foldlevelstart=99
silent! set colorcolumn=+1
silent! set helpheight=10
silent! set laststatus=2
silent! set mouse=a
silent! set number
silent! set pumheight=16
silent! set ruler
silent! set showcmd
silent! set scrolloff=4
silent! set sidescrolloff=8
silent! set sidescroll=1
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
silent! set ignorecase
silent! set smartcase
silent! set completeopt=menuone
silent! set wildmenu
silent! set wildoptions+=fuzzy,pum
silent! set hlsearch
silent! set incsearch
silent! set ttimeout
silent! set ttimeoutlen=0
silent! set autoindent
silent! set shortmess-=S
silent! set sessionoptions+=globals
silent! set viminfo=!,'100,<50,s10,h
silent! set diffopt+=algorithm:histogram,indent-heuristic
silent! set clipboard^=unnamedplus
silent! set formatoptions+=n
silent! set jumpoptions=stack

" Spell check
silent! set spell
silent! set spellcapcheck=''
silent! set spelllang=en_us
silent! set spelloptions=camel
silent! set spellsuggest=best,9

" Focus events
silent! let &t_fe = "\<Esc>[?1004h"
silent! let &t_fd = "\<Esc>[?1004l"

" Set editor to vim
silent! let $EDITOR = 'vim'
silent! let $VISUAL = 'vim'

" Align columns in quickfix window
silent! set quickfixtextfunc=Qftf

" param: info dict
" return: string[]
function! Qftf(info) abort
  let qflist = a:info['quickfix']
        \ ? getqflist(#{id: a:info.id, items: 0}).items
        \ : getloclist(a:info.winid, #{id: a:info.id, items: 0}).items

  if len(qflist) == 0
    return []
  endif

  let fname_width = 0
  let lnum_width  = 0
  let col_width   = 0
  let type_width  = 0
  let nr_width    = 0
  let max_width   = &columns / 2

  let fname_str_cache = []
  let lnum_str_cache  = []
  let col_str_cache   = []
  let type_str_cache  = []
  let nr_str_cache    = []

  let fname_width_cache = []
  let lnum_width_cache  = []
  let col_width_cache   = []
  let type_width_cache  = []
  let nr_width_cache    = []

  for item in qflist
    let fname = get(item, 'module')
          \ ? item.module : (get(item, 'filename')
            \ ? item.filename : fnamemodify(bufname(item.bufnr), ':~:.'))
    let lnum = item.lnum == item.end_lnum || item.end_lnum == 0
          \ ? item.lnum
          \ : item.lnum . '-' . item.end_lnum
    let col = item.col == item.end_col
          \ ? item.col
          \ : item.col . '-' . item.end_col
    let type = trim(item.type) != '' ? ' ' .. trim(item.type) : ''
    let nr = item.nr > 0 ? ' ' .. item.nr : ''

    let fname_cur_width = strdisplaywidth(fname)
    let lnum_cur_width  = strdisplaywidth(lnum)
    let col_cur_width   = strdisplaywidth(col)
    let type_cur_width  = strdisplaywidth(type)
    let nr_cur_width    = strdisplaywidth(nr)

    let fname_width = min([max_width, max([fname_width, fname_cur_width])])
    let lnum_width  = min([max_width, max([lnum_width,  lnum_cur_width])])
    let col_width   = min([max_width, max([col_width,   col_cur_width])])
    let type_width  = min([max_width, max([type_width,  type_cur_width])])
    let nr_width    = min([max_width, max([nr_width,    nr_cur_width])])

    call add(fname_str_cache, fname)
    call add(lnum_str_cache,  lnum)
    call add(col_str_cache,   col)
    call add(type_str_cache,  type)
    call add(nr_str_cache,    nr)

    call add(fname_width_cache, fname_cur_width)
    call add(lnum_width_cache,  lnum_cur_width)
    call add(col_width_cache,   col_cur_width)
    call add(type_width_cache,  type_cur_width)
    call add(nr_width_cache,    nr_cur_width)
  endfor

  let result = []
  for idx in range(len(qflist))
    let item = qflist[idx]

    if !item.valid
      continue
    endif

    let fname = fname_str_cache[idx]
    let fname_cur_width = fname_width_cache[idx]

    if item.lnum == 0 && item.col == 0 && item.text == ''
      call add(result, fname)
      continue
    endif

    let lnum = lnum_str_cache[idx]
    let col = col_str_cache[idx]
    let type = type_str_cache[idx]
    let nr = nr_str_cache[idx]

    let lnum_cur_width = lnum_width_cache[idx]
    let col_cur_width = col_width_cache[idx]
    let type_cur_width = type_width_cache[idx]
    let nr_cur_width = nr_width_cache[idx]

    call add(result, printf('%s|%s:%s%s%s| %s',
          \ fname . repeat(' ', fname_width - fname_cur_width),
          \ repeat(' ', lnum_width - lnum_cur_width) . lnum,
          \ col . repeat(' ', col_width - col_cur_width),
          \ type . repeat(' ', type_width - type_cur_width),
          \ nr . repeat(' ', nr_width   - nr_cur_width),
          \ item.text))
  endfor

  return result
endfunction

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

" Set keymap that only when the trigger is at the position of a command
" param: trig string
" param: command string
" param: a:1 flags string? '<expr>'/'<buffer>',etc
function! s:command_map(trig, command, ...) abort
  if exists('*getcmdcompltype')
    exe printf(
          \ 'cnoremap %s %s getcmdcompltype() ==# "command" ? "%s" : "%s"',
          \ '<expr>' . substitute(get(a:, 1, ''), '<expr>', '', ''),
          \ a:trig,
          \ escape(a:command, '"\'),
          \ escape(a:trig, '"\'))
  endif
endfunction

call s:command_map(':', 'lua ')
call s:command_abbrev('tt', 'tab ter')
call s:command_abbrev('bt', 'bot ter')
call s:command_abbrev('ht', 'hor ter')
call s:command_abbrev('vt', 'vert ter')
call s:command_abbrev('rm', '!rm')
call s:command_abbrev('mv', '!mv')
call s:command_abbrev('git', '!git')
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

" Autosave on focus lost, window/buf leave, etc. {{{2
if s:supportevents(['BufLeave', 'WinLeave', 'FocusLost'])
  function! s:auto_save(buf, file) abort
    if getbufvar(a:buf, '&bt', '') ==# ''
      silent! update
    endif
  endfunction
  augroup AutoSave
    au!
    if has('patch-8.1113')
      au BufLeave,WinLeave,FocusLost * ++nested
            \ :call s:auto_save(expand('<abuf>'), expand('<afile>'))
    else
      au BufLeave,WinLeave,FocusLost *
            \ :call s:auto_save(expand('<abuf>'), expand('<afile>'))
    endif
  augroup END
endif
" }}}2

" Open quickfix/location list automatically when set with commands {{{2
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
" }}} 2

" Make all widnows the same height/width on vim resized {{{2
if s:supportevents('VimResized')
  augroup EqualWinSize
    au!
    au VimResized * wincmd =
  augroup END
endif
" }}}

" Restore last position when opening a file {{{2
if s:supportevents('BufReadPost')
  augroup LastPosJmp
    au!
    au BufReadPost * if &ft !=# 'gitcommit' && &ft !=# 'gitrebase' |
          \ exe 'silent! normal! g`"zvzz' |
          \ endif
  augroup END
endif
" }}}2

" Jump to last accessed window on closing the current one {{{2
if s:supportevents('WinClosed')
  augroup WinCloseJmp
    au!
    if has('patch-8.1113')
      au WinClosed * ++nested if expand('<amatch>') == win_getid() |
            \ wincmd p |
            \ endif
    else
      au WinClosed * if expand('<amatch>') == win_getid() |
            \ wincmd p |
            \ endif
    endif
  augroup END
endif
" }}}2

" Automatically setting cwd to the root directory {{{2
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
        \ '.git',
        \ '.svn',
        \ '.bzr',
        \ '.hg',
        \ '.project',
        \ '.pro',
        \ '.sln',
        \ '.vcxproj',
        \ 'Makefile',
        \ 'makefile',
        \ 'MAKEFILE',
        \ 'venv',
        \ 'env',
        \ '.venv',
        \ '.env',
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
      exe 'silent! lcd ' . proj_dir
      return
    endif
    let dirname = fnamemodify(fpath, ':p:h')
    if isdirectory(dirname)
      exe 'silent! lcd ' . dirname
    endif
  endfunction

  augroup AutoCwd
    au!
    autocmd BufReadPost,BufWinEnter,FileChangedShellPost * ++nested
          \ if &bt == '' && &ma | call <SID>autocwd(expand('<afile>')) | endif
  augroup END
endif
" }}}2

" Colorscheme persistence over restarts {{{2
"
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
    au VimEnter    * :call s:theme_restore()
    au ColorScheme * :call s:theme_save()
    au ColorScheme * :call s:theme_fix_hlspell()
  augroup END
endif
" }}}2

" Clear strange escape sequence shown when using alt keys to navigate away {{{2
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
    " Keep cursor position after finishing visual mode replacement when virtual
    " edit is enabled
    au ModeChanged [vV\x16]*:n if &ve =~# 'all' && exists('w:ve_cursor') |
          \ call cursor([w:ve_cursor[1], w:ve_cursor[2] + w:ve_cursor[3]]) |
          \ endif
  augroup END
endif
" }}}2

" Consistent &iskeyword in Ex command-line {{{2
if s:supportevents(['CmdlineEnter', 'CmdlineLeave'])
  augroup FixCmdLineIskeyword
    au!
    au CmdlineEnter [:>/?=@] let g:_isk_lisp_buf = str2nr(expand('<abuf>')) |
          \ let g:_isk_save = getbufvar(g:_isk_lisp_buf, '&isk', '') |
          \ let g:_lisp_save = getbufvar(g:_isk_lisp_buf, '&lisp', 0) |
          \ setlocal isk& lisp&
    au CmdlineLeave [:>/?=@] if
            \ exists('g:_isk_lisp_buf') && bufexists(g:_isk_lisp_buf) |
          \ call setbufvar(g:_isk_lisp_buf, '&isk', g:_isk_save) |
          \ call setbufvar(g:_isk_lisp_buf, '&lisp', g:_lisp_save) |
          \ unlet g:_isk_save g:_lisp_save g:_isk_lisp_buf |
          \ endif
endif
" }}}2

" Clear invalid buffers after loading session {{{2
if s:supportevents('SessionLoadPost')
  function! s:clear_invalid_buffers()
    for buf in getbufinfo()
      if line('$') <= 1 &&
            \ getbufline(buf.bufnr, 1, 2) == [''] &&
            \ !filereadable(bufname(l:buf.bufnr))
        exe 'bd! ' . buf.bufnr
      endif
    endfor
  endfunction

  augroup SessionClearInvalidBufs
    autocmd!
    autocmd SessionLoadPost * call s:clear_invalid_buffers()
  augroup END
endif
" }}}2
" }}}1

""" Keymaps {{{1
" Leader & localleader keys {{{2
let g:mapleader = ' '
let g:maplocalleader = ' '
" }}}2

" Past with correct indentation in insert mode {{{2
inoremap <C-r> <C-r><C-p>
" }}}

" Delete selection in select mode {{{2
snoremap <BS>  <C-o>s
snoremap <C-h> <C-o>s
" }}}

" Moving up & down in visual line {{{2
nnoremap <expr> j        v:count ? "j"      : "gj"
xnoremap <expr> j        v:count ? "j"      : "gj"
nnoremap <expr> k        v:count ? "k"      : "gk"
xnoremap <expr> k        v:count ? "k"      : "gk"
nnoremap <expr> <Down>   v:count ? "<Down>" : "g<Down>"
xnoremap <expr> <Down>   v:count ? "<Down>" : "g<Down>"
nnoremap <expr> <Up>     v:count ? "<Up>"   : "g<Up>"
xnoremap <expr> <Up>     v:count ? "<Up>"   : "g<Up>"

inoremap <Down> <C-o>g<Down>
inoremap <Up>   <C-o>g<Up>
" }}}2

" Switching buffers {{{2
nnoremap <silent> ]b :exec v:count1 . 'bn'<CR>
nnoremap <silent> [b :exec v:count1 . 'bp'<CR>
" }}}

" Switching between quickfix/location list items {{{2
nnoremap <silent> [q :exec v:count1 . 'cp'<CR>
nnoremap <silent> [l :exec v:count1 . 'lp'<CR>
nnoremap <silent> ]p :exec v:count1 . 'lne'<CR>
nnoremap <silent> ]l :exec v:count1 . 'cne'<CR>
nnoremap <silent> [Q :exec v:count1 . 'cfir'<CR>
nnoremap <silent> [L :exec v:count1 . 'lfir'<CR>
nnoremap <silent> ]Q :exec (v:count ? v:count : '') . 'cla'<CR>
nnoremap <silent> ]L :exec (v:count ? v:count : '') . 'lla'<CR>
" }}}

" Tabpages {{{2
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
xnoremap <silent> gt :<C-u>call TabSwitch('tabnext')<CR>
xnoremap <silent> gT :<C-u>call TabSwitch('tabprev')<CR>
" }}}2

" Spell {{{2
inoremap <C-g>+ <Esc>[szg`]a
inoremap <C-g>= <C-g>u<Esc>[s1z=`]a<C-G>u
" }}}

" Selecting around quotes without extra spaces {{{2
xmap a" 2i"
xmap a' 2i'
xmap a` 2i`
omap a" 2i"
omap a' 2i'
omap a` 2i`
" }}}2

" Edit current file path {{{2
nnoremap -      :e%:p:h<CR>
xnoremap - <Esc>:e%:p:h<CR>
" }}}2

" Enter insert mode with a space after the cursor {{{2
nnoremap <Esc>i i<Space><Left>
xnoremap <Esc>I I<Space><Left>
nnoremap <Esc>a a<Space><Left>
xnoremap <Esc>A A<Space><Left>
" }}}2

" Jump to the fisrt/last line in paragraph {{{2
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
" }}}2

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
          \ . (a:motion ==# 'i' ? ']zkV[zj' : ']zV[z')
  endif
  return (foldlev == 0 ? 'zj'
        \ : (foldlev > foldlev_prev ? 'j' : ''))
        \ . (a:motion ==# 'i' ? '[zjV]zk' : '[zV]z')
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
nnoremap <silent> &     :&&<CR>
xnoremap <silent> *     y/\V<C-R>=escape(@",'/')<CR><CR>
xnoremap <silent> #     y?\V<C-R>=escape(@",'/')<CR><CR>
nnoremap <silent> <C-l> :nohlsearch\|diffupdate<CR><C-l>
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
  exe map . '<Esc>p       <C-w>p'
  exe map . '<Esc>r       <C-w>r'
  exe map . '<Esc>v       <C-w>v'
  exe map . '<Esc>s       <C-w>s'
  exe map . '<Esc>x       <C-w>x'
  exe map . '<Esc>z       <C-w>z'
  exe map . '<Esc>c       <C-w>c'
  exe map . '<Esc>q       <C-w>q'
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
  exe map . '<Esc><Left>  <C-w><Left>'
  exe map . '<Esc><Down>  <C-w><Down>'
  exe map . '<Esc><Up>    <C-w><Up>'
  exe map . '<Esc><Right> <C-w><Right>'
  exe map . '<Esc>g<Esc>] <C-w>g<C-]>'
  exe map . '<Esc>g<Tab>  <C-w>g<Tab>'

  exe map . '<expr> <Esc>+ v:count ? "<C-w>+" : "2<C-w>+"'
  exe map . '<expr> <Esc>- v:count ? "<C-w>-" : "2<C-w>-"'
  exe map . '<expr> <C-w>+ v:count ? "<C-w>+" : "2<C-w>+"'
  exe map . '<expr> <C-w>- v:count ? "<C-w>-" : "2<C-w>-"'
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
endfor
" }}}2

" Readline keymaps {{{2
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
  return s:match_nonempty(str[colnr - 1:],
        \ '^\s*[[:keyword:]]*', '^\s*[^[:keyword:] ]*')
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
        \ '[[:keyword:]]*\s*$',
        \ '[^[:keyword:] ]*\s*$')
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
        \ . repeat("\<Left>", strlen(s:get_word_before(line_str,
                                                      \ strlen(line_str))))
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

" Callback function for small delete, e.g. `<C-w>`, `<M-BS>`, `<M-d>`, `<C-k>`,
" `<C-u>`, etc keymaps; sets the small delete register '-' properly, should be
" used " with `{ expr = true }`
" param: text_deleted string
" param: forward 0/1
" return: string
function! s:ic_small_del(text_deleted, forward) abort
  " Lock to prevent next deletion before current deletion action completes.
  " If we don't set this lock we might get and save wrong (old) cursor position
  " in CmdlineChanged/TextChangedI callbacks, which will cause the '-' register
  " to be reset undesirably.
  if get(g:, '_rl_del_lock') || a:text_deleted == ''
    return ''
  endif
  let g:_rl_del_lock = 1

  let in_cmdline = mode() == 'c'
  " We want to concat the deleted text in the '-' register if we are deleting
  " 'continuously'. In insert mode, 'continuously' means that, after previous
  " deletion, ther is no changes in the buffer and the cursor stays in the
  " same position; in cmdline mode, this means we are editing the same command
  " line (both type and contents) and the cursor poistion is the same after
  " previous deletion.
  " In ohter cases, we reset the '-' register with the new deleted text.
  let reset = !(in_cmdline
        \ ? getcmdline() == get(g:, '_rl_cmd') &&
          \ getcmdtype() == get(g:, '_rl_cmd_type') &&
          \ getcmdpos() == get(g:, '_rl_cmd_pos')
        \ : b:changedtick == get(b:, '_rl_changedtick') &&
          \ getcurpos() == get(b:, '_rl_del_pos'))
  let reg_contents = reset ? '' : getreg('-')
  let reg_new_contents = a:forward ? reg_contents . a:text_deleted
        \ : a:text_deleted . reg_contents
  call setreg('-', reg_new_contents)

  " Record the cursor position after deleting the text
  if in_cmdline
    " Defer setting `g:_rl_cmd*` because CmdlineChanged is triggered BEFORE
    " the actual change happens, however we want to get the command line
    " contents, type and curosr position AFTER the change happens so that
    " we can decide whether to concat the contents in the small-delete register
    if exists('*timer_start')
      autocmd CmdlineChanged * ++once call timer_start(0,
            \ {-> execute('let g:_rl_cmd = getcmdline() |'
                      \ . 'let g:_rl_cmd_pos = getcmdpos() |'
                      \ . 'let g:_rl_cmd_type = getcmdtype() |'
                      \ . 'let g:_rl_del_lock = 0')})
    else
      " If `timer_start()` does not exist, we still need to unlock
      " `g:_rl_del_lock` to allow next small deletion
      autocmd CmdlineChanged * ++once let g:_rl_del_lock = 0
    endif
  else
    autocmd TextChangedI * ++once
          \ let b:_rl_del_pos = getcurpos() |
          \ let b:_rl_changedtick = b:changedtick |
          \ let g:_rl_del_lock = 0
  endif

  " Set 'sts' and 'sw' to 1 temporarily to avoid removing multiple chars at
  " once on one `<BS>`
  if !a:forward && !in_cmdline
    let b:_rl_sts = &sts
    let b:_rl_sw = &sw
    let &sts = 1
    let &sw = 1
    autocmd TextChangedI * ++once
          \ if exists('b:_rl_sts') && exists('b:_rl_sw') |
            \ let &sts = b:_rl_sts |
            \ let &sw = b:_rl_sw |
            \ unlet b:_rl_sts |
            \ unlet b:_rl_sw |
          \ endif
  endif

  " Use `<C-g>u` to start a new change for each word deletion
  return (in_cmdline ? '' : "\<C-g>u")
        \ . repeat(a:forward ? "\<Del>" : "\<BS>", strlen(a:text_deleted))
endfunction

function! s:ic_ctrl_a() abort
  let current_line = s:get_current_line()
  return "\<Home>" . (current_line[:max([0, s:get_current_col() - 2])] =~# '\S'
        \ ? repeat("\<Right>", strlen(matchstr(current_line, '^\s*')))
        \ : '')
endfunction

function! s:ic_ctrl_e() abort
  return pumvisible() ? "\<C-e>" : "\<End>"
endfunction

function! s:ic_ctrl_y() abort
  return pumvisible() ? "\<C-y>" : "\<C-r>-"
endfunction

if exists('*timer_start')
  function! s:i_ctrl_y() abort
    if pumvisible()
      call feedkeys("\<C-y>", 'n')
      return
    endif

    let linenr = line('.')
    let colnr = col('.')
    let current_line = getline('.')
    let lines = split(getreg('-'), "\n", 1)
    let lines[0] = current_line[:max([0, colnr - 2])] . lines[0]
    let target_cursor = [
          \ linenr + len(lines) - 1,
          \ strlen(lines[len(lines) - 1]) + 1]
    let lines[-1] = lines[-1] . current_line[colnr - 1:]

    function! InoreCtrlYSetLines(_) abort closure
      call feedkeys("\<C-g>u", 'n')
      call setline(linenr, lines[0])
      call append(linenr, lines[1:])
      call cursor(target_cursor[0], target_cursor[1])
    endfunction

    call timer_start(0, 'InoreCtrlYSetLines')
  endfunction

  inoremap <expr> <C-y> <SID>i_ctrl_y()
  cnoremap <expr> <C-y> <SID>ic_ctrl_y()
else
  noremap! <expr> <C-y> <SID>ic_ctrl_y()
endif

" <M-Del>
map! <Esc>[3;3~ <C-w>

noremap! <C-d>  <Del>
cnoremap <C-b>  <Left>
cnoremap <C-f>  <Right>
cnoremap <C-o>  <C-f>

inoremap <expr> <C-b>  <SID>i_ctrl_b()
inoremap <expr> <C-f>  <SID>i_ctrl_f()
noremap! <expr> <Esc>f <SID>ic_meta_f()
noremap! <expr> <Esc>b <SID>ic_meta_b()
noremap! <expr> <C-a>  <SID>ic_ctrl_a()
noremap! <expr> <C-e>  <SID>ic_ctrl_e()

if s:supportevents(['TextChangedI', 'CmdlineChanged']) && has('patch-8.1.1113')
  " `ic_small_del()` requires support for `TextChangedI`, `CmdlineChanged`
  " events and the `++once` argument (patch-8.1.1113)
  function! s:ic_ctrl_w() abort
    return s:ic_small_del(s:start_of_line() && !s:first_line()
          \ ? "\n"
          \ : s:get_word_before(), 0)
  endfunction

  function! s:ic_ctrl_u() abort
    let line_before = s:get_current_line()[0:max([0, s:get_current_col() - 2])]
    return s:ic_small_del(s:start_of_line() && !s:first_line()
          \ ? "\n"
          \ : (line_before =~# '\S'
            \ ? substitute(line_before, '^\s*', '', '')
            \ : line_before), 0)
  endfunction

  function! s:ic_ctrl_k() abort
    return s:ic_small_del(s:end_of_line() && !s:last_line()
          \ ? "\n"
          \ : s:get_current_line()[s:get_current_col() - 1:], 1)
  endfunction

  function! s:ic_meta_d() abort
    return s:ic_small_del(s:end_of_line() && !s:last_line()
          \ ? "\n"
          \ : s:get_word_after(), 1)
  endfunction

  noremap! <expr> <C-w>  <SID>ic_ctrl_w()
  noremap! <expr> <C-u>  <SID>ic_ctrl_u()
  noremap! <expr> <C-k>  <SID>ic_ctrl_k()
  noremap! <expr> <Esc>d <SID>ic_meta_d()
else
  function! s:ic_ctrl_k() abort
    return (mode() == 'c' ? '' : "\<C-g>u")
          \ . repeat("\<Del>",
            \ strlen(s:get_current_line()[s:get_current_col() - 1:]))
  endfunction

  function! s:ic_meta_d() abort
    return (mode() == 'c' ? '' : "\<C-g>u")
          \ . repeat("\<Del>", strlen(s:get_word_after()))
  endfunction

  noremap! <expr> <C-k>  <SID>ic_ctrl_k()
  noremap! <expr> <Esc>d <SID>ic_meta_d()
endif
" }}}2
" }}}1

""" Plugin Settings {{{1
" Netrw {{{2
let g:netrw_banner = 0
let g:netrw_cursor = 5
let g:netrw_keepdir = 0
let g:netrw_keepj = ''
let g:netrw_list_hide = '\(^\|\s\s\)\zs\.\S\+'
let g:netrw_liststyle = 1
let g:netrw_localcopydircmd = 'cp -r'

if s:supportevents('FileType')
  augroup NetrwSettings
    au!
    au FileType netrw setlocal
          \ bufhidden=hide
          \ buftype=nofile
          \ nobuflisted
          \ nolist
          \ nonumber
          \ norelativenumber
          \ nospell
          \ colorcolumn=
          \ signcolumn=no
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

" " Use fzf as file explorer
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
" " }}}2
" " }}}1

""" Misc {{{1
" Terminal Settings {{{2

if exists(':tmap') == 2
  " Check if any of the processes in current terminal is a TUI app
  " return: 0/1
  function! s:running_tui() abort
    for cmd in s:fg_cmds()
      if cmd =~# '\v^(sudo(\s+--?(\w|-)+((\s+|\=)\S+)?)*\s+)?\S*
          \(n?vim?|vimdiff|emacs(client)?|lem|nano|helix|kak|
          \tmux|vifm|yazi|ranger|lazygit|h?top|gdb|fzf|nmtui|
          \sudoedit|ssh|crontab|asciinema|w3m)'
        return 1
      endif
    endfor
  endfunction

  " Default <C-w> is used as 'termwinkey' (see :h 'termwinkey')
  " which conflicts with shell's keymap
  tnoremap <nowait> <C-w> <C-\><C-w>

  " Use <C-\><C-r> to insert contents of a register in terminal mode
  tnoremap <expr> <C-\><C-r> (&twk ? &twk : '<C-w>') . '"' . nr2char(getchar())

  " Workaround to avoid <M-...> keymaps in terminal mode to be interpreted to
  " <Esc> + ... (seperate keystrokes) given `<Esc>` is mapped to itself
  " with argument `<nowait>` in terminal mode
  for char in split("ABCDEFGHIJKLMNOPQRSTUVWXYZ
        \abcdefghijklmnopqrstuvwxyz
        \0123456789`~!@#$%^&*()-_=+[]{}\\|;:'\",.<>/?", '.\zs')
    let char_esc = escape(char, '\|')
    exe printf('tnoremap <Esc>%s <Esc>%s', char_esc, char_esc)
  endfor

  tnoremap <expr> <C-6>   <SID>running_tui() ? '<C-6>'   : '<C-\><C-n>:b#<CR>'
  tnoremap <expr> <C-^>   <SID>running_tui() ? '<C-^>'   : '<C-\><C-n>:b#<CR>'
  tnoremap <expr> <Esc>v  <SID>running_tui() ? '<Esc>v'  : '<C-\><C-n><C-w>vi'
  tnoremap <expr> <Esc>s  <SID>running_tui() ? '<Esc>s'  : '<C-\><C-n><C-w>si'
  tnoremap <expr> <Esc>W  <SID>running_tui() ? '<Esc>W'  : '<C-\><C-n><C-w>Wi'
  tnoremap <expr> <Esc>H  <SID>running_tui() ? '<Esc>H'  : '<C-\><C-n><C-w>Hi'
  tnoremap <expr> <Esc>J  <SID>running_tui() ? '<Esc>J'  : '<C-\><C-n><C-w>Ji'
  tnoremap <expr> <Esc>K  <SID>running_tui() ? '<Esc>K'  : '<C-\><C-n><C-w>Ki'
  tnoremap <expr> <Esc>L  <SID>running_tui() ? '<Esc>L'  : '<C-\><C-n><C-w>Li'
  tnoremap <expr> <Esc>r  <SID>running_tui() ? '<Esc>r'  : '<C-\><C-n><C-w>ri'
  tnoremap <expr> <Esc>R  <SID>running_tui() ? '<Esc>R'  : '<C-\><C-n><C-w>Ri'
  tnoremap <expr> <Esc>o  <SID>running_tui() ? '<Esc>o'  : '<C-\><C-n><C-w>oi'
  tnoremap <expr> <Esc>x  <SID>running_tui() ? '<Esc>x'  : '<C-\><C-n><C-w>x'
  tnoremap <expr> <Esc>p  <SID>running_tui() ? '<Esc>p'  : '<C-\><C-n><C-w>p'
  tnoremap <expr> <Esc>c  <SID>running_tui() ? '<Esc>c'  : '<C-\><C-n><C-w>c'
  tnoremap <expr> <Esc>q  <SID>running_tui() ? '<Esc>q'  : '<C-\><C-n><C-w>q'
  tnoremap <expr> <Esc>w  <SID>running_tui() ? '<Esc>w'  : '<C-\><C-n><C-w>w'
  tnoremap <expr> <Esc>h  <SID>running_tui() ? '<Esc>h'  : '<C-\><C-n><C-w>h'
  tnoremap <expr> <Esc>j  <SID>running_tui() ? '<Esc>j'  : '<C-\><C-n><C-w>j'
  tnoremap <expr> <Esc>k  <SID>running_tui() ? '<Esc>k'  : '<C-\><C-n><C-w>k'
  tnoremap <expr> <Esc>l  <SID>running_tui() ? '<Esc>l'  : '<C-\><C-n><C-w>l'
  tnoremap <expr> <Esc><Left>  <SID>running_tui() ? '<Esc><Left>'  : '<C-\><C-n><C-w><Left>'
  tnoremap <expr> <Esc><Down>  <SID>running_tui() ? '<Esc><Down>'  : '<C-\><C-n><C-w><Down>'
  tnoremap <expr> <Esc><Up>    <SID>running_tui() ? '<Esc><Up>'    : '<C-\><C-n><C-w><Up>'
  tnoremap <expr> <Esc><Right> <SID>running_tui() ? '<Esc><Right>' : '<C-\><C-n><C-w><Right>'
  tnoremap <expr> <Esc>=  <SID>running_tui() ? '<Esc>='  : '<C-\><C-n><C-w>=i'
  tnoremap <expr> <Esc>_  <SID>running_tui() ? '<Esc>_'  : '<C-\><C-n><C-w>_i'
  tnoremap <expr> <Esc>\| <SID>running_tui() ? '<Esc>\|' : '<C-\><C-n><C-w>\|i'
  tnoremap <expr> <Esc>+  <SID>running_tui() ? '<Esc>+'  : '<C-\><C-n><C-w>2+i'
  tnoremap <expr> <Esc>-  <SID>running_tui() ? '<Esc>-'  : '<C-\><C-n><C-w>2-i'
  if has('patch-8.1.1140')
    tnoremap <expr> <Esc>> <SID>running_tui() ? '<Esc>>' : '<C-\><C-n><C-w>4' . (winnr() == winnr('l') ? '<' : '>') . 'i'
    tnoremap <expr> <Esc>< <SID>running_tui() ? '<Esc><' : '<C-\><C-n><C-w>4' . (winnr() == winnr('l') ? '>' : '<') . 'i'
    tnoremap <expr> <Esc>. <SID>running_tui() ? '<Esc>.' : '<C-\><C-n><C-w>4' . (winnr() == winnr('l') ? '<' : '>') . 'i'
    tnoremap <expr> <Esc>, <SID>running_tui() ? '<Esc>,' : '<C-\><C-n><C-w>4' . (winnr() == winnr('l') ? '>' : '<') . 'i'
  else
    tnoremap <expr> <Esc>> <SID>running_tui() ? '<Esc>>' : '<C-\><C-n><C-w>4>i'
    tnoremap <expr> <Esc>< <SID>running_tui() ? '<Esc><' : '<C-\><C-n><C-w>4<i'
    tnoremap <expr> <Esc>. <SID>running_tui() ? '<Esc>.' : '<C-\><C-n><C-w>4>i'
    tnoremap <expr> <Esc>, <SID>running_tui() ? '<Esc>,' : '<C-\><C-n><C-w>4<i'
  endif
endif

if s:supportevents('TerminalWinOpen')
  " return: reltime() converted to ms
  function! s:reltime_ms() abort
    let t = reltime()
    return t[0] * 1000 + t[1] / 1000000
  endfunction

  " Get the command running in the foreground in current terminal
  " return: string[]: command running in the foreground
  function! s:fg_cmds() abort
    if &buftype !~# 'terminal'
      return []
    endif

    let cmds = []
    for stat_cmd_str in split(system('ps h -o stat,args -g '
          \ . job_info(term_getjob(bufnr())).process), '\n')
      let stat_cmd = split(stat_cmd_str, '\s\+', 0)
      if stat_cmd[0] =~# '^\S\++' " check if this is a foreground process
        call add(cmds, stat_cmd[1])
      endif
    endfor

    return cmds
  endfunction

  augroup TermOptions
    au!
    au TerminalWinOpen * setlocal nonu nornu scl=no bh=hide so=0 siso=0 |
          \ nnoremap <expr><buffer> p 'i' . (&twk ? &twk : '<C-w>') . '"' . v:register . '<C-\><C-n>'|
          \ nnoremap <expr><buffer> P 'i' . (&twk ? &twk : '<C-w>') . '"' . v:register . '<C-\><C-n>'|
          \ startinsert
  augroup END
endif
" }}}2

" Navigate tmux panes using vim-style motions {{{2
if $TMUX !=# '' && $TMUX_PANE !=# '' && has('patch-8.1.1140')
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

  nnoremap <silent> <Esc><Left>  :<C-u>call <SID>navigate('h', v:count1)<CR>
  nnoremap <silent> <Esc><Down>  :<C-u>call <SID>navigate('j', v:count1)<CR>
  nnoremap <silent> <Esc><Up>    :<C-u>call <SID>navigate('k', v:count1)<CR>
  nnoremap <silent> <Esc><Right> :<C-u>call <SID>navigate('l', v:count1)<CR>

  xnoremap <silent> <Esc><Left>  :<C-u>call <SID>navigate('h', v:count1)<CR>
  xnoremap <silent> <Esc><Down>  :<C-u>call <SID>navigate('j', v:count1)<CR>
  xnoremap <silent> <Esc><Up>    :<C-u>call <SID>navigate('k', v:count1)<CR>
  xnoremap <silent> <Esc><Right> :<C-u>call <SID>navigate('l', v:count1)<CR>

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

  " return funcref
  function! s:tmux_mapkey_navigate_condition(direction) abort
    return {-> (s:vim_at_border(a:direction) || s:vim_in_popup_win())
          \ && s:tmux_should_move(a:direction)}
  endfunction
  let TmuxMapkeyNavigateLeftCondition  = s:tmux_mapkey_navigate_condition('h')
  let TmuxMapkeyNavigateDownCondition  = s:tmux_mapkey_navigate_condition('j')
  let TmuxMapkeyNavigateUpCondition    = s:tmux_mapkey_navigate_condition('k')
  let TmuxMapkeyNavigateRightCondition = s:tmux_mapkey_navigate_condition('l')

  " param: command string|funcref
  " param: key_fallback string
  " param: condition? fun(): boolean
  " return: string (rhs)
  function! s:tmux_mapkey_fallback(command, key_fallback, ...) abort
    let Condition = get(a:, 1, g:TmuxMapKeyDefaultConditionRef)
    if ! Condition() || mode() =~# '^t' && s:running_tui() || $VIM_TERMINAL
      return a:key_fallback
    endif
    if type(a:command) == v:t_string
      call s:tmux_exec(a:command)
      return
    endif
    call a:command() " a:command is funcref
  endfunction

  nnoremap <expr><silent> <Esc>p <SID>tmux_mapkey_fallback('last-pane', '<C-w>p')
  nnoremap <expr><silent> <Esc>R <SID>tmux_mapkey_fallback('swap-pane -U', '<C-w>R')
  nnoremap <expr><silent> <Esc>r <SID>tmux_mapkey_fallback('swap-pane -D', '<C-w>r')
  nnoremap <expr><silent> <Esc>o <SID>tmux_mapkey_fallback("confirm 'kill-pane -a'", '<C-w>o')
  nnoremap <expr><silent> <Esc>= <SID>tmux_mapkey_fallback("confirm 'select-layout tiled'", '<C-w>=')
  nnoremap <expr><silent> <Esc>c <SID>tmux_mapkey_fallback('confirm kill-pane', '<C-w>c', TmuxMapkeyCloseWinConditionRef)
  nnoremap <expr><silent> <Esc>q <SID>tmux_mapkey_fallback('confirm kill-pane', '<C-w>q', TmuxMapkeyCloseWinConditionRef)
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
  xnoremap <expr><silent> <Esc>q <SID>tmux_mapkey_fallback('confirm kill-pane', '<C-w>q', TmuxMapkeyCloseWinConditionRef)
  xnoremap <expr><silent> <Esc>< <SID>tmux_mapkey_fallback('resize-pane -L 4', (v:count ? '' : 4) . (winnr() == winnr('l') ? '<C-w>>' : '<C-w><'), TmuxMapkeyResizePaneHorizConditionRef)
  xnoremap <expr><silent> <Esc>> <SID>tmux_mapkey_fallback('resize-pane -R 4', (v:count ? '' : 4) . (winnr() == winnr('l') ? '<C-w><' : '<C-w>>'), TmuxMapkeyResizePaneHorizConditionRef)
  xnoremap <expr><silent> <Esc>, <SID>tmux_mapkey_fallback('resize-pane -L 4', (v:count ? '' : 4) . (winnr() == winnr('l') ? '<C-w>>' : '<C-w><'), TmuxMapkeyResizePaneHorizConditionRef)
  xnoremap <expr><silent> <Esc>. <SID>tmux_mapkey_fallback('resize-pane -R 4', (v:count ? '' : 4) . (winnr() == winnr('l') ? '<C-w><' : '<C-w>>'), TmuxMapkeyResizePaneHorizConditionRef)
  xnoremap <expr><silent> <Esc>- <SID>tmux_mapkey_fallback("run \"tmux resize-pane -y $(($(tmux display -p '#{pane_height}') - 2))\"", v:count ? '<C-w>-' : '2<C-w>-', TmuxMapkeyResizePaneVertConditionRef)
  xnoremap <expr><silent> <Esc>+ <SID>tmux_mapkey_fallback("run \"tmux resize-pane -y $(($(tmux display -p '#{pane_height}') + 2))\"", v:count ? '<C-w>+' : '2<C-w>+', TmuxMapkeyResizePaneVertConditionRef)

  if exists(':tmap') == 2
    tnoremap <expr><silent> <Esc>h <SID>tmux_mapkey_fallback({-> <SID>navigate('h')}, <SID>running_tui() ? '<Esc>h' : '<C-\><C-n><C-w>h', TmuxMapkeyNavigateLeftCondition)
    tnoremap <expr><silent> <Esc>j <SID>tmux_mapkey_fallback({-> <SID>navigate('j')}, <SID>running_tui() ? '<Esc>j' : '<C-\><C-n><C-w>j', TmuxMapkeyNavigateDownCondition)
    tnoremap <expr><silent> <Esc>k <SID>tmux_mapkey_fallback({-> <SID>navigate('k')}, <SID>running_tui() ? '<Esc>k' : '<C-\><C-n><C-w>k', TmuxMapkeyNavigateUpCondition)
    tnoremap <expr><silent> <Esc>l <SID>tmux_mapkey_fallback({-> <SID>navigate('l')}, <SID>running_tui() ? '<Esc>l' : '<C-\><C-n><C-w>l', TmuxMapkeyNavigateRightCondition)

    tnoremap <expr><silent> <Esc><Left>  <SID>tmux_mapkey_fallback({-> <SID>navigate('h')}, <SID>running_tui() ? '<Esc><Left>'  : '<C-\><C-n><C-w><Left>',  TmuxMapkeyNavigateLeftCondition)
    tnoremap <expr><silent> <Esc><Down>  <SID>tmux_mapkey_fallback({-> <SID>navigate('j')}, <SID>running_tui() ? '<Esc><Down>'  : '<C-\><C-n><C-w><Down>',  TmuxMapkeyNavigateDownCondition)
    tnoremap <expr><silent> <Esc><Up>    <SID>tmux_mapkey_fallback({-> <SID>navigate('k')}, <SID>running_tui() ? '<Esc><Up>'    : '<C-\><C-n><C-w><Up>',    TmuxMapkeyNavigateUpCondition)
    tnoremap <expr><silent> <Esc><Right> <SID>tmux_mapkey_fallback({-> <SID>navigate('l')}, <SID>running_tui() ? '<Esc><Right>' : '<C-\><C-n><C-w><Right>', TmuxMapkeyNavigateRightCondition)

    tnoremap <expr><silent> <Esc>p <SID>tmux_mapkey_fallback('last-pane', <SID>running_tui() ? '<Esc>p'  : '<C-\><C-n><C-w>p')
    tnoremap <expr><silent> <Esc>r <SID>tmux_mapkey_fallback('swap-pane -D', <SID>running_tui() ? '<Esc>r'  : '<C-\><C-n><C-w>ri')
    tnoremap <expr><silent> <Esc>R <SID>tmux_mapkey_fallback('swap-pane -U', <SID>running_tui() ? '<Esc>R'  : '<C-\><C-n><C-w>Ri')
    tnoremap <expr><silent> <Esc>o <SID>tmux_mapkey_fallback("confirm 'kill-pane -a'", <SID>running_tui() ? '<Esc>o'  : '<C-\><C-n><C-w>oi')
    tnoremap <expr><silent> <Esc>= <SID>tmux_mapkey_fallback("confirm 'select-layout tiled'", <SID>running_tui() ? '<Esc>='  : '<C-\><C-n><C-w>=i')
    tnoremap <expr><silent> <Esc>c <SID>tmux_mapkey_fallback('confirm kill-pane', <SID>running_tui() ? '<Esc>c'  : '<C-\><C-n><C-w>c', TmuxMapkeyCloseWinConditionRef)
    tnoremap <expr><silent> <Esc>q <SID>tmux_mapkey_fallback('confirm kill-pane', <SID>running_tui() ? '<Esc>q'  : '<C-\><C-n><C-w>q', TmuxMapkeyCloseWinConditionRef)
    tnoremap <expr><silent> <Esc>< <SID>tmux_mapkey_fallback('resize-pane -L 4', <SID>running_tui() ? '<Esc><' : '<C-\><C-n><C-w>4' . (winnr() == winnr('l') ? '>' : '<') . 'i', TmuxMapkeyResizePaneHorizConditionRef)
    tnoremap <expr><silent> <Esc>> <SID>tmux_mapkey_fallback('resize-pane -R 4', <SID>running_tui() ? '<Esc>>' : '<C-\><C-n><C-w>4' . (winnr() == winnr('l') ? '<' : '>') . 'i', TmuxMapkeyResizePaneHorizConditionRef)
    tnoremap <expr><silent> <Esc>, <SID>tmux_mapkey_fallback('resize-pane -L 4', <SID>running_tui() ? '<Esc>,' : '<C-\><C-n><C-w>4' . (winnr() == winnr('l') ? '>' : '<') . 'i', TmuxMapkeyResizePaneHorizConditionRef)
    tnoremap <expr><silent> <Esc>. <SID>tmux_mapkey_fallback('resize-pane -R 4', <SID>running_tui() ? '<Esc>.' : '<C-\><C-n><C-w>4' . (winnr() == winnr('l') ? '<' : '>') . 'i', TmuxMapkeyResizePaneHorizConditionRef)
    tnoremap <expr><silent> <Esc>- <SID>tmux_mapkey_fallback("run \"tmux resize-pane -y $(($(tmux display -p '#{pane_height}') - 2))\"", <SID>running_tui() ? '<Esc>-'  : '<C-\><C-n><C-w>2-i', TmuxMapkeyResizePaneVertConditionRef)
    tnoremap <expr><silent> <Esc>+ <SID>tmux_mapkey_fallback("run \"tmux resize-pane -y $(($(tmux display -p '#{pane_height}') + 2))\"", <SID>running_tui() ? '<Esc>+'  : '<C-\><C-n><C-w>2+i', TmuxMapkeyResizePaneVertConditionRef)
  endif

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
    au FileType qf if win_gettype() ==# 'quickfix' | wincmd J | endif |
          \ silent! setlocal nobl nolist nospell nornu scl=no cc=0 |
          \ silent! packadd cfilter
  augroup END
endif
" }}}2

" Workaround to prevent <Esc> lag cause by Meta keymaps {{{2
noremap  <nowait> <Esc> <Esc>
noremap! <nowait> <Esc> <C-\><C-n>
if exists(':tmap') == 2
  tnoremap       <nowait> <Esc> <Esc>
  tnoremap <expr><nowait> <Esc> <SID>running_tui() ? '<Esc>' : '<C-\><C-n>'
endif
" }}}2
" }}}1

" vim:tw=79:ts=2:sts=2:sw=2:et:fdm=marker:fdl=0:ft=vim:norl:
