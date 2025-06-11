" Vim compiler file
" Compiler:         Go Test
" Maintainer:       Bekaboo <kankefengjing@gmail.com>
" Latest Revision:  Mon Jun  9 20:03:28 2025

if exists("g:current_compiler")
  finish
endif
let g:current_compiler = "gotest"

let s:cpo_save = &cpo
set cpo&vim

if exists('g:gotest_makeprg_params')
  CompilerSet makeprg=go\ test\ '.escape(g:gotest_makeprg_params, ' \|"').'\ $*'
else
  CompilerSet makeprg=go\ test\ $*
endif

CompilerSet errorformat=
CompilerSet errorformat+=%-G%\\s%#===\ RUN\ %.%#            " Ignore === RUN TestXXX
CompilerSet errorformat+=%-G%\\s%#---\ PASS:\ %.%#          " Ignore --- PASS: TestXXX
CompilerSet errorformat+=%-G%\\s%#---\ FAIL:\ %.%#          " Ignore --- FAIL: TestXXX
CompilerSet errorformat+=%-GFAIL%.%#                        " Ignore FAIL github.com/usr/pkg...
CompilerSet errorformat+=%-Gok\ %m                          " Ignore ok github.com/usr/pkg...

CompilerSet errorformat+=%E%\\s%#Error\ Trace:%\\s%\\+%f:%l " Start of multi-line error: Error Trace: some_test.go:123
CompilerSet errorformat+=%Z%\\s%#Messages:%\\s%\\+%m        " End of multi-line error: Messages: msg...
CompilerSet errorformat+=%C%\\s%#%m                         " Multi-line error message continuation
CompilerSet errorformat+=%C                                 " Multi-line error message continuation
CompilerSet errorformat+=%-G%.%#                            " Ignore lines that does not match any of the patterns above

" Example go test error output:
"
" --- FAIL: TestValidateTestSuite (4.98s)
"     --- FAIL: TestValidateTestSuite/TestExtractReferencedResourceIDs (0.00s)
"         --- FAIL: TestValidateTestSuite/TestExtractReferencedResourceIDs/extract_kb_id_single (0.00s)
"             validate_test.go:531:
"                         Error Trace:    /Users/bekaboo/code/inc/go-servers/bot-server/internal/virtualagent/validate_test.go:531
"                                                                 /Users/bekaboo/go/pkg/mod/github.com/stretchr/testify@v1.10.0/suite/suite.go:115
"                         Error:          elements differ
"
"                                         extra elements in list A:
"                                         ([]interface {}) (len=1) {
"                                          (string) (len=6) "kb-123"
"                                         }
"
"
"                                         extra elements in list B:
"                                         ([]interface {}) (len=1) {
"                                          (string) (len=5) "kb123"
"                                         }
"
"
"                                         listA:
"                                         ([]string) (len=1) {
"                                          (string) (len=6) "kb-123"
"                                         }
"
"
"                                         listB:
"                                         ([]string) (len=1) {
"                                          (string) (len=5) "kb123"
"                                         }
"                         Test:           TestValidateTestSuite/TestExtractReferencedResourceIDs/extract_kb_id_single
"                         Messages:       extracted knowledge base IDs mismatch
" FAIL
" FAIL    github.com/inc/go-servers/bot-server/internal/virtualagent   5.260s
" FAIL

let &cpo = s:cpo_save
unlet s:cpo_save
