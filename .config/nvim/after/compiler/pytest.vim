" Make vim-dispatch pick shipped pytest compiler plugin for `python3 -m pytest`
" command, see
" - `:h dispatch-:Dispatch`
" - `$VIMRUNTIME/compiler/pytest.vim`
CompilerSet makeprg=python3\ -m\ pytest

" Remove '%+G...' formats to avoid including general messages without
" corresponding file locations in quickfix
for efm in split(&efm, ',')
  if efm =~# '%+G'
    exe 'CompilerSet errorformat-=' . escape(efm, '\\ ')
  endif
endfor

" Ignore lines with timestamps in json, e.g. "2025-06-14 22:29:59" which can be
" confused with the `filename:line:column` pattern
CompilerSet errorformat^=%-G%.%#\"%\\d%\\{4}-%\\d%\\{2}-%\\d%\\{2}\ %\\d%\\{2}:%\\d%\\{2}%.%#
