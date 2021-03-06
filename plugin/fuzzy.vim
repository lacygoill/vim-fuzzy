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

command! -bar -nargs=? FzCommands fuzzy#main('Commands', <q-args>)
command! -bar -nargs=? FzFiles fuzzy#main('Files', <q-args>)
command! -bar -nargs=? FzGrep fuzzy#main('Grep', <q-args>)
command! -bar -nargs=? FzHelpTags fuzzy#main('HelpTags', <q-args>)
command! -bar -nargs=? FzLocate fuzzy#main('Locate', <q-args>)

nnoremap <unique> <Space>fc <Cmd>call fuzzy#main('Commands')<CR>
nnoremap <unique> <Space>ff <Cmd>call fuzzy#main('Files')<CR>
nnoremap <unique> <Space>fgg <Cmd>call fuzzy#main('Grep')<CR>
nnoremap <unique> <Space>fh <Cmd>call fuzzy#main('HelpTags')<CR>
# How is `Locate` useful compared to `Files`?{{{
#
# `locate(1)` is much faster than `find(1)` and `fd(1)`.
# And it can find *all* the files, not just the ones in the cwd.
#}}}
nnoremap <unique> <Space>fl <Cmd>call fuzzy#main('Locate')<CR>

nnoremap <unique> <Space>fmn <Cmd>call fuzzy#main('Mappings (n)')<CR>
nnoremap <unique> <Space>fmx <Cmd>call fuzzy#main('Mappings (x)')<CR>
nnoremap <unique> <Space>fmi <Cmd>call fuzzy#main('Mappings (i)')<CR>
nnoremap <unique> <Space>fmo <Cmd>call fuzzy#main('Mappings (o)')<CR>

nnoremap <unique> <Space>fr <Cmd>call fuzzy#main('RecentFiles')<CR>

nnoremap <unique> "<C-F> <Cmd>call fuzzy#main('Registers"')<CR>
nnoremap <unique> @<C-F> <Cmd>call fuzzy#main('Registers@')<CR>
inoremap <unique> <C-R><C-F> <Cmd>call fuzzy#main('Registers<C-R>')<CR>
