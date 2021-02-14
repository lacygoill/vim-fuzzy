vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

nno <space>fc <cmd>call fuzzy#main('Commands')<cr>
nno <space>ff <cmd>call fuzzy#main('Files')<cr>
nno <space>fgg <cmd>call fuzzy#main('Grep')<cr>
nno <space>fh <cmd>call fuzzy#main('HelpTags')<cr>
# How is `Locate` useful compared to `Files`?{{{
#
# `locate(1)` is much faster than `find(1)` and `fd(1)`.
# And it can find *all* the files, not just the ones in the cwd.
#}}}
nno <space>fl <cmd>call fuzzy#main('Locate')<cr>

nno <space>fmn <cmd>call fuzzy#main('Mappings (n)')<cr>
nno <space>fmx <cmd>call fuzzy#main('Mappings (x)')<cr>
nno <space>fmi <cmd>call fuzzy#main('Mappings (i)')<cr>
nno <space>fmo <cmd>call fuzzy#main('Mappings (o)')<cr>

nno <space>fr <cmd>call fuzzy#main('RecentFiles')<cr>
