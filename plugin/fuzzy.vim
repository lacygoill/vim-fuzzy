vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# TODO: For each mapping, implement the counterpart Ex command.
# It would be especially useful for huge sources.
# For example:
#
#     :Files
#     # too many lines; the plugin is slow, or it bails out
#
#     :Files pat
#     # much fewer lines; the plugin is fast, or at least it doesn't bail out
#
# If we supply an  initial pattern to an Ex command, we should  never be able to
# remove any character from it (be it with `C-u`, `C-h`, `BS`).

com! -bar -nargs=? FzCommands fuzzy#main('Commands', <q-args>)
com! -bar -nargs=? FzFiles fuzzy#main('Files', <q-args>)
com! -bar -nargs=? FzGrep fuzzy#main('Grep', <q-args>)
com! -bar -nargs=? FzHelpTags fuzzy#main('HelpTags', <q-args>)
com! -bar -nargs=? FzLocate fuzzy#main('Locate', <q-args>)

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

nno "<c-f> <cmd>call fuzzy#main('Registers"')<cr>
nno @<c-f> <cmd>call fuzzy#main('Registers@')<cr>
ino <c-r><c-f> <cmd>call fuzzy#main('Registers<c-r>')<cr>
