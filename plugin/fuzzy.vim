vim9script

if exists('g:loaded_fuzzy')
    finish
endif
g:loaded_fuzzy = 1

com -nargs=* FuzzyHelp fuzzy#main('help', <q-args>)
nno <silent> <space>fh :<c-u>FuzzyHelp<cr>

com -nargs=* FuzzyRecentFiles fuzzy#main('recentfiles', <q-args>)
nno <silent> <space>fr :<c-u>FuzzyRecentFiles<cr>
