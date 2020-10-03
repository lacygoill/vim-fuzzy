vim9script

com -nargs=* FuzzyHelp fuzzy#help(<q-args>)
nno <silent> <space>fh :<c-u>FuzzyHelp<cr>

