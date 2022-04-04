vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

import autoload '../autoload/fuzzy.vim'

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

command! -bar -nargs=? FzCommands fuzzy.Main('Commands', <q-args>)
command!      -nargs=? FzFiles fuzzy.Main('Files', <q-args>)
command!      -nargs=? FzGrep fuzzy.Main('Grep', <q-args>)
command! -bar -nargs=? FzHelpTags fuzzy.Main('HelpTags', <q-args>)
command!      -nargs=? FzLocate fuzzy.Main('Locate', <q-args>)
# Don't use `-bar` for commands whose argument might contain a double quote.

nnoremap <unique> <Space>fc <ScriptCmd>fuzzy.Main('Commands')<CR>
nnoremap <unique> <Space>ff <ScriptCmd>fuzzy.Main('Files')<CR>
nnoremap <unique> <Space>fgg <ScriptCmd>fuzzy.Main('Grep')<CR>
nnoremap <unique> <Space>fh <ScriptCmd>fuzzy.Main('HelpTags')<CR>
# How is `Locate` useful compared to `Files`?{{{
#
# `locate(1)` is much faster than `find(1)` and `fd(1)`.
# And it can find *all* the files, not just the ones in the cwd.
#}}}
nnoremap <unique> <Space>fl <ScriptCmd>fuzzy.Main('Locate')<CR>

nnoremap <unique> <Space>fmn <ScriptCmd>fuzzy.Main('Mappings (n)')<CR>
nnoremap <unique> <Space>fmx <ScriptCmd>fuzzy.Main('Mappings (x)')<CR>
nnoremap <unique> <Space>fmi <ScriptCmd>fuzzy.Main('Mappings (i)')<CR>
nnoremap <unique> <Space>fmo <ScriptCmd>fuzzy.Main('Mappings (o)')<CR>

nnoremap <unique> <Space>fr <ScriptCmd>fuzzy.Main('RecentFiles')<CR>

nnoremap <unique> "<C-F> <ScriptCmd>fuzzy.Main('Registers"')<CR>
nnoremap <unique> @<C-F> <ScriptCmd>fuzzy.Main('Registers@')<CR>
inoremap <unique> <C-R><C-F> <ScriptCmd>fuzzy.Main('Registers<C-R>')<CR>
