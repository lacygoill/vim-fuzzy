vim9script

if exists('g:loaded_fuzzy')
    finish
endif
g:loaded_fuzzy = 1

com -nargs=* FuzzyHelp fuzzy#help(<q-args>)
nno <silent> <space>fh :<c-u>FuzzyHelp<cr>

