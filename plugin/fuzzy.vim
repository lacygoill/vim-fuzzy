vim9script

if exists('g:loaded_fuzzy')
    finish
endif
g:loaded_fuzzy = 1

nno <silent> <space>fc :<c-u>call fuzzy#main('Commands')<cr>
nno <silent> <space>ff :<c-u>call fuzzy#main('Files')<cr>
nno <silent> <space>fh :<c-u>call fuzzy#main('HelpTags')<cr>

nno <silent> <space>fmn :<c-u>call fuzzy#main('Mappings (n)')<cr>
nno <silent> <space>fmx :<c-u>call fuzzy#main('Mappings (x)')<cr>
nno <silent> <space>fmi :<c-u>call fuzzy#main('Mappings (i)')<cr>
nno <silent> <space>fmo :<c-u>call fuzzy#main('Mappings (o)')<cr>

nno <silent> <space>fr :<c-u>call fuzzy#main('RecentFiles')<cr>
