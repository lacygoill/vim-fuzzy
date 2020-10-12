vim9script

if exists('g:loaded_fuzzy')
    finish
endif
g:loaded_fuzzy = 1

nno <silent> <space>fh :<c-u>call fuzzy#main('Help')<cr>
nno <silent> <space>fr :<c-u>call fuzzy#main('RecentFiles')<cr>

nno <silent> <space>fmn :<c-u>call fuzzy#main('Mappings', 'n')<cr>
nno <silent> <space>fmx :<c-u>call fuzzy#main('Mappings', 'x')<cr>
nno <silent> <space>fmi :<c-u>call fuzzy#main('Mappings', 'i')<cr>
nno <silent> <space>fmo :<c-u>call fuzzy#main('Mappings', 'o')<cr>

