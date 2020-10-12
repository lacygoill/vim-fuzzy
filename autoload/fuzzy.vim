vim9script

# I want to be able to edit my input!{{{
#
# For now, I don't know how to do that.
#
# We've only implemented 2 basic editing commands (`C-u` and `C-h`).
# And we  simply use `:echo` to  give us some  visual feedback as to  what we've
# typed so far.
#
# Suggestion1: Ask for a new builtin popup menu filter.
# It would be different than the existing one in 2 fundamental ways:
#
#    - it would cause Vim to automatically create an extra popup, below the popup
#      for which it filters the keypresses
#
#    - instead of receiving each keypress, the filter would receive the whole text
#      typed so far in the extra popup, but only when it has changed (i.e. it would
#      ignore motions)
#
# Maybe the extra  popup leverage the concept of  prompt buffer...
#
# Suggestion2: There has been some discussion on Google regarding a feature
# request originally posted on github:
# https://github.com/vim/vim/issues/5639
# https://groups.google.com/g/vim_dev/c/42DjcXhuVAE/m/8yzxkBysAQAJ
#
# The original feature request was asking to make a popup window focusable.
# At some point in  the discussion, someone mentions that it  would be useful to
# implement a fuzzy finder:
#
#    > For fuzzy finder style popup it also becomes important.
#    > I have tried multiple approaches ie. using custom prompt similar to ctrlp,
#    > denite style where the prompt is a buffer.
#    > I'm leaning to denite style pattern but that means it won't work in popup.
#    > vim-clap already seems to be hitting this issue.
#
# It has been acknowledged in the todo list.  From `:h todo /^Popup`
#
#    > Popup windows:
#    > - Add a flag to make a popup window focusable?
#
# You could wait for this todo item  to be implemented, and test whether you can
# use the new feature to get an editable prompt.
#}}}

if !executable('grep') || !executable('perl') || !executable('awk')
    echohl WarningMsg
    echom ':Fuzzy* commands require grep and perl/awk'
    echohl None
    finish
endif

# TODO: Implement a mechanism which lets us mark multiple lines in the popup.
# Use the sign column to display a sign besides any marked line.

# TODO: Implement a  mechanism which  allows us  to run  arbitrary code  when we
# press another key then Enter to close the popup.
# For example,  if we press `C-q`,  we might want  all the selected lines  to be
# used to populate the qfl.
# Once done, post your solution here: <https://github.com/junegunn/fzf/issues/1885>

# TODO: Implement `:FuzzyCommands`.
# Also, consider implementing various `:FuzzyMappings`; one for each mode.

# TODO: Implement `:FuzzyAutoCommands`.

# TODO: Implement `:FuzzyFiles`.

# TODO: Implement `:FuzzyGrep`.
# https://vi.stackexchange.com/questions/10692/how-to-interactively-search-grep-with-vim/10693#10693
#
#     $ grep -RHn '.*' .
#                      ^
#                      Vim's cwd

# TODO: Implement `:FuzzyBuffer`.
# https://vi.stackexchange.com/questions/308/regex-that-prefers-shorter-matches-within-a-match-this-is-more-involved-than-n

const TEXTWIDTH = 80
# 2 popups = 4 borders
const BORDERS = 4

var filter_text = ''
var preview_winid = 0
var menu_winid = 0

var source: list<dict<string>>
var filtered_source: list<dict<string>>
var sourcetype: string
var mappings_mode = ''

# Interface {{{1
def fuzzy#main(type: string, _mappings_mode = '') #{{{2
    sourcetype = type

    var height = &lines / 3
    var statusline = &ls == 2 || &ls == 1 && winnr('$') >= 2 ? 1 : 0
    var tabline = &stal == 2 || &stal == 1 && tabpagenr('$') >= 2 ? 1 : 0
    def Offset(): number
        var offset = 0
        var necessary = 2 * height + BORDERS
        var available = &lines - &ch - statusline - tabline
        if necessary > available
            offset = (necessary - available) / 2
            if (necessary - available) % 2 == 1
                offset += 1
            endif
        endif
        return offset
    enddef
    height -= Offset()
    if height <= 0
        echohl ErrorMsg
        echom '[:Fuzzy' .. sourcetype .. '] Not enough room'
        echohl NONE
        return
    endif

    var width = min([TEXTWIDTH, &columns - BORDERS])
    var line = &lines - &ch - statusline - height - 1

    var opts = #{
        line: line,
        col: (&columns - TEXTWIDTH - BORDERS) / 2,
        pos: 'topleft',
        maxheight: height,
        minheight: height,
        maxwidth: width,
        minwidth: width,
        # Set a title displaying some info about the numbers of entries we're dealing with.{{{
        #
        # Example:
        #
        #     12/34 (56)
        #     ├┘ ├┘  ├┘
        #     │  │   └ there were 56 help lines originally
        #     │  └ there are 34 lines remaining
        #     └ we're selecting the 12th line
        #}}}
        title: ' 0/0 (0)',
        highlight: 'Normal',
        borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
        scrollbar: false,
        filter: FilterLines,
        callback: function(ExitCallback, [sourcetype]),
        }

    # create popup menu
    menu_winid = popup_menu('', opts)
    prop_type_add('fuzzy', #{bufnr: winbufnr(menu_winid), highlight: 'Title'})
    # highlight the location from which mappings have been installed
    # TODO: It would  probably be better  to use text properties,  and highlight
    # the `trailing` key.   It would give us the highlighting  for free, as long
    # as we we properly set `trailing`.
    if sourcetype == 'Mappings'
        matchadd('Comment', '\S\+:\d\+$', 10, -1, #{window: menu_winid})
    endif

    # create preview
    opts = popup_getoptions(menu_winid)
    extend(opts, #{line: opts.line - (height + BORDERS / 2)})
    remove(opts, 'callback')
    remove(opts, 'cursorline')
    remove(opts, 'filter')
    remove(opts, 'title')
    preview_winid = popup_create('', opts)

    mappings_mode = _mappings_mode
    InitSource()
enddef
#}}}1
# Core {{{1
def InitSource() #{{{2
    if sourcetype == 'Help'
        InitHelpTags()
    elseif sourcetype == 'Mappings'
        InitMappings()
    elseif sourcetype == 'RecentFiles'
        InitRecentFiles()
    endif

    # For   sources   of   data   obtained  asynchronously,   we   must   invoke
    # `SetFilteredSource()`   from  elsewhere:    `SetIntermediateSource()`  and
    # `SetFinalSource()`.
    if index(['Help'], sourcetype) >= 0
        return
    endif
    SetFilteredSource()
enddef

def InitHelpTags() #{{{2
    var tagfiles = globpath(&rtp, 'doc/tags', true, true)

    # What's the purpose of this formatting command?{{{
    #
    # It should format the output of `grep(1)` so that:
    #
    #    - the path of the tagfile is removed at the start
    #    - the tag regex is removed at the end (`/*some-tag*`)
    #    - the tag name is left-aligned in a 40 bytes string
    #
    # Basically, we want to go from this:
    #
    #                                       tab
    #                                     v------v
    #     /home/user/.fzf/doc/tags:fzf-toc        fzf.txt /*fzf-toc*
    #                              ^-----^        ^-----^
    #                              we're only interested in this
    #
    # To that:
    #
    #     fzf-toc                                 fzf.txt
    #}}}
    #   But I can do the same thing in Vim!{{{
    #
    # Yes, but you can't make Vim functions like `printf()` async.
    # OTOH, you *can* make perl or awk async with `job_start()`.
    #
    # Besides, perl is much faster than Vim (≈ 6 times).
    #}}}
    var formatting_cmd: string
    # give the preference to perl, because it's more than twice faster than awk on our machine
    if executable('perl')
        # What is{{{
        #}}}
        #   `-n`{{{
        #
        # It makes perl iterate over the input lines somewhat like awk.
        #
        # See `man perlrun /^\s*-n`.
        #}}}
        #   `-e`{{{
        #
        # It makes perl execute the code from the next string argument.
        # Without, perl would look for a filename from which to read the program.
        #
        # See `man perlrun /^\s*-e`.
        #}}}
        #   `.*?`{{{
        #
        # `*?` is a lazy quantifier, equivalent to `\{-}` in Vim.
        # So, `.*?` is the same as `.\{-}` in Vim.
        #
        # See `man perlreref /QUANTIFIERS/;/\*?`.
        #}}}
        #   `qq`{{{
        #
        # An operator which quotes a string.
        # See `man perlop /^\s*Quote-Like Operators/;/qq`
        #}}}
        formatting_cmd = 'perl -n -e ''/.*?:(.*?)\t(.*?)\t/; printf(qq/%-40s\t%s\n/, $1, $2)'''
    else
        var awkpgm =<< trim END
            {
                match($0, "[^:]*:([^\t]*)\t([^\t]*)\t", a);
                printf("%-40s\t%s\n", a[1], a[2]);
            }
        END
        formatting_cmd = 'awk ' .. join(awkpgm, '')->shellescape()
    endif

    var shellpipeline = 'grep -H ".*" '
        .. map(tagfiles, {_, v -> shellescape(v)})
            ->sort()
            ->uniq()
            ->join()
        .. ' | ' .. formatting_cmd
        .. ' | sort'

    # The shell command might take too long.  Let's start it asynchronously.{{{
    #
    # Right now, it takes about `.17s` which doesn't seem a lot.
    # But it's  noticeable; too  much for a  tool like a  fuzzy finder.
    # Besides, this duration might be longer on another machine.
    # Also, remember that  we want to extend this plugin  to support other kinds
    # of sources (not just  help tags).  Some of them might  be much bigger, and
    # in that case, the shell command might take a much longer time.
    #}}}
    job_start(['/bin/sh', '-c', shellpipeline], #{
        out_cb: SetIntermediateSource,
        exit_cb: SetFinalSource,
        mode: 'raw',
        noblock: true,
        })
enddef

def InitMappings() #{{{2
    source = execute('verb ' .. mappings_mode .. 'map')
        # remove first empty lines
        ->substitute('^\%(\s*\n\)*', '', '')
        # split after every "Last set from ..." line
        ->split('\n\s*Last set from [^\n]* line \d\+\zs\n')
        # transforms each pair of lines into a dictionary
        ->map({_, v -> #{
            # `matchstr()` removes the mode (`n`, `nox`, ...).{{{
            # `substitute()` removes some special characters:
            #
            #     x  =rd         *@:RefDot<CR>
            #                    ^^
            #                    noise
            #}}}
            text: matchstr(v, '...\zs[^\n]*')->substitute('^\S*\s\+\zs[*&]\=[@ ]\=', '', ''),
            # `matchstr()` extracts the filename.{{{
            #
            #     Last set from /path/to/script.vim line 123
            #                            ^--------^
            #
            # And `substitute()` replaces ` line 123` into `:123`.
            #}}}
            trailing: "\t" .. matchstr(v, '/\zs[^/\\]*$')->substitute(' [^ ]* ', ':', '')
            }})

    # align all the lhs in a field (max 35 cells)
    var longest_lhs = source
        ->deepcopy()
        ->map({_, v -> v.text->matchstr('^\S*')->strchars(true)})
        ->max()
    longest_lhs = min([35, longest_lhs])
    source->map({_, v -> extend(v, #{
        text: matchstr(v.text, '^\S*')->printf('%-' .. longest_lhs .. 'S')
            .. ' ' .. matchstr(v.text, '^\S*\s\+\zs.*')
        })})

    # TODO: For each mapping, make the preview display where it's installed from.
    # Also, make the preview window include a title which displays the path to the file.
    # This could be  useful when the mapping  is so long that we  can't see from
    # where it's installed in the main popup.
enddef

def InitRecentFiles() #{{{2
    var recentfiles: list<string> = BuflistedSorted()
        + copy(v:oldfiles)->filter({_, v -> expand(v)->filereadable()})
    map(recentfiles, {_, v -> fnamemodify(v, ':p')})
    var curbuf = expand('%:p')
    source = recentfiles
        ->filter({_, v -> v != '' && v != curbuf && !isdirectory(v)})
        ->Uniq()
        ->map({_, v -> #{text: fnamemodify(v, ':~:.'), trailing: ''}})
enddef

def SetFilteredSource() #{{{2
    filtered_source = source
        ->copy()
        ->filter({_, v -> v.text =~ filter_text})
    UpdatePopup()
enddef

def SetIntermediateSource(_c: channel, data: string) #{{{2
    var _data: string
    if incomplete != ''
        _data = incomplete .. data
    else
        _data = data
    endif
    var splitted_data = split(_data, '\n\ze.')
    # The last line of `data` does not necessarily match a full shell output line.
    # Most of the time, it's incomplete.
    incomplete = remove(splitted_data, -1)
    if len(splitted_data) == 0
        return
    endif

    # Turn the strings into dictionaries to easily ignore some arbitrary trailing part when filtering.{{{
    #
    # For example, if we're  looking for a help tag, we  probably don't want our
    # typed text  to be matched against  the filename.  Otherwise, we  might get
    # too many irrelevant results (test with the pattern "changes").
    #}}}
    source += splitted_data
        ->map({_, v -> split(v, '\t')})
        ->map({_, v -> #{text: v[0], trailing: v[1]}})

    # Need to be  set now, in case  we don't write any filtering  text, and just
    # press Enter  on whatever entry is  the first; otherwise, we  won't jump to
    # the right tag.
    SetFilteredSource()
enddef
var incomplete = ''

def SetFinalSource(...l: any) #{{{2
    # Wait for all callbacks to have been processed.{{{
    #
    # From `:h job-exit_cb`:
    #
    #    > Note that data can be buffered, callbacks may still be
    #    > called after the process ends.
    #
    # Without this sleep, sometimes, `parts[1]` would raise:
    #
    #     E684: list index out of range: 1
    #}}}
    sleep 1m
    var parts = split(incomplete, '\t')
    # need to  be cleared now, otherwise,  the last help tag  will be duplicated
    # the next time we run `:FuzzyHelp`
    incomplete = ''
    source += [#{text: parts[0], trailing: parts[1]->trim("\<c-j>")}]
    #                                                     ^------^
    #                        the last line of the shell ouput ends
    #                        with an undesirable trailing newline
    SetFilteredSource()
enddef

def FilterLines(id: number, key: string): bool #{{{2
# Handle the keys typed in the popup menu.
# Narrow down the lines based on the keys typed so far.

    # filter the names based on the typed key and keys typed before;
    # the pattern is taken from the regex used in the syntax group `helpHyperTextEntry`
    if key =~ '^[#-)!+-~]$' || key == "\<space>"
        filter_text ..= key
        UpdatePopup()
        return true

    # clear the filter text entirely
    elseif key == "\<c-u>"
        filter_text = ''
        UpdatePopup()
        return true

    # erase only one character from the filter text
    elseif key == "\<bs>" || key == "\<c-h>"
        if len(filter_text) >= 1
            filter_text = filter_text[:-2]
            UpdatePopup()
        endif
        return true

    # select a neighboring line
    elseif index(["\<down>", "\<up>", "\<c-n>", "\<c-p>"], key) >= 0
        # No need to update the popup if we try to move beyond the first/last line.{{{
        #
        # Besides, if  you let Vim  update the popup  in those cases,  it causes
        # some  annoying flickering  in the  popup title  when we  keep pressing
        # `C-n` or `C-p` for a bit too long.  Note that `id` (function argument)
        # and `menu_winid` (script local) have the same value.
        #}}}
        if key == "\<up>" && line('.', id) == 1
        || key == "\<c-p>" && line('.', id) == 1
        || key == "\<down>" && line('.', id) == line('$', id)
        || key == "\<c-n>" && line('.', id) == line('$', id)
            return true
        endif
        var cmd = 'norm! ' .. (key == "\<c-n>" || key == "\<down>" ? 'j' : 'k')
        win_execute(id, cmd)
        UpdatePopup(false)
        return true

    # allow for the preview to be scrolled
    elseif key == "\<m-j>" || key == "\<f21>"
        win_execute(preview_winid, ['setl cul', 'norm! j'])
        return true
    elseif key == "\<m-k>" || key == "\<f22>"
        win_execute(preview_winid, ['setl cul', 'norm! k'])
        return true
    # reset the cursor position in the preview popup
    elseif key == "\<m-r>" || key == "\<f29>"
        UpdatePreview()
        return true

    # prevent title from  flickering when `CursorHold` is fired, and  we have at
    # least one autocmd listening
    elseif key == "\<CursorHold>"
        return true
    endif

    return popup_filter_menu(id, key)
enddef

def UpdatePopup(popup = true) #{{{2
    if popup
        UpdateMain()
    endif

    # no need to  update the preview on every keypress,  when we're typing fast;
    # update only when we've paused for at least 50ms
    if preview_timer > 0
        timer_stop(preview_timer)
        preview_timer = 0
    endif
    preview_timer = timer_start(50, {-> UpdatePreview()})

    UpdateTitle()
enddef
var preview_timer = 0

def UpdateMain() #{{{2
# update the popup with the new list of lines
    var highlighted_lines: list<dict<any>>
    if filter_text =~ '\S'
        var matchfuzzypos: list<any>
        # Problem: We can't pass the typed text to `matchfuzzypos()` directly.{{{
        #
        # If we type a whitespace-separated list of token, we want to:
        #
        #    - ignore the whitespace
        #    - look for the tokens in all possible orders
        #
        # `matchfuzzypos()` will not look for the tokens in all possible orders,
        # and won't even ignore whitespace.
        #}}}
        # Solution:{{{
        #
        # Split the  string on every  whitespace, compute all  permutations, run
        # `matchfuzzypos()` on each permutation, and join the results.
        #}}}
        var tokens = split(filter_text)
        # Problem: `matchfuzzypos()` gets too slow as the number of tokens increases.{{{
        #
        # 4 tokens = 24 permutations = 24 invocations of `matchfuzzypos()`.
        #}}}
        # Solution: Limit the splitting to 3 tokens max.{{{
        #
        # Note   that   this   already   generates   6   permutations,   causing
        # `matchfuzzypos()` to be  invoked 6 times, which  is already noticeable
        # (i.e. a keypress slightly lags when you have 3 tokens).
        #}}}
        # TODO: This might be too slow when there are a lot of lines.
        # You might want  to replace `4` with a number  which takes into account
        # the type of source, or better yet, the number of lines.
        if len(tokens) >= 4
            var rest = tokens[2:]->join()->substitute('\s\+', '', 'g')
            tokens = [tokens[0], tokens[1], rest]
        endif
        matchfuzzypos = tokens
            ->Permutations()
            ->map({_, v -> join(v, '')})
            ->map({_, v -> matchfuzzypos(source, v, #{key: 'text'})})
            ->reduce({a, v -> [a[0] + v[0], a[1] + v[1]]})

        var pos: list<list<number>>
        # Why using `filtered_source` to save `matchfuzzypos()`?{{{
        #
        # It needs  to be  updated now,  so that  `ExitCallback()` jumps  to the
        # right tag later.
        #}}}
        [filtered_source, pos] = matchfuzzypos

        # add info to get highlight via text properties
        highlighted_lines = filtered_source
            ->map({i, v -> #{
                text: v.text .. "\t" .. v.trailing,
                props: map(pos[i], {_, w -> #{col: w + 1, length: 1, type: 'fuzzy'}}),
                }})
    else
        highlighted_lines = source
            ->copy()
            ->map({_, v -> #{
                text: v.text .. "\t" .. v.trailing,
                props: [],
                }})
    endif
    popup_settext(menu_winid, highlighted_lines)
    # select first entry after every change of the filtering text (to mimic what fzf does)
    win_execute(menu_winid, 'norm! 1G')

    echohl ModeMsg
    if sourcetype == 'Mappings'
        echo sourcetype .. ' (' .. mappings_mode .. '): '
    else
        echo sourcetype->substitute('\l\zs\ze\u', ' ', 'g') .. ': '
    endif
    echohl Title
    echon filter_text
    echohl NONE
enddef

def UpdatePreview() #{{{2
    var splitted = winbufnr(menu_winid)
        ->getbufline(line('.', menu_winid))
        ->get(0, '')
        ->split('\t')
    var left = ''
    var right = ''
    if len(splitted) == 2
        [left, right] = splitted
    elseif len(splitted) == 1
        left = splitted[0]
    else
        return
    endif

    var filename: string
    if sourcetype == 'Help'
        # Why passing "true, true" as argument to `globpath()`?{{{
        #
        # The  first  `true` can  be  useful  if  for  some reason  `'suffixes'`  or
        # `'wildignore'` are misconfigured.
        # The second  `true` is useful to  handle the case where  `globpath()` finds
        # several files.  It's easier to extract the first one from a list than from
        # a string.
        #}}}
        filename = globpath(&rtp, 'doc/' .. right, true, true)->get(0, '')
    elseif sourcetype == 'RecentFiles'
        filename = expand(left)->fnamemodify(':p')
    endif
    if !filereadable(filename)
        return
    endif

    var text = readfile(filename)
    popup_settext(preview_winid, text)

    # syntax highlight the text and make sure the cursor is at the relevant location
    if sourcetype == 'Help'
        var setsyntax = [
            'if get(b:, "current_syntax", "") != "help"',
            'do Syntax help',
            'endif'
            ]
        var tagname = left->trim()->substitute("'", "''", 'g')->escape('\')
        var searchcmd = printf("echo search('\\*\\V%s\\m\\*')", tagname)
        # Why not just running `search()`?{{{
        #
        # If you just run `search()`, Vim won't redraw the preview popup.
        # You'll need to run `:redraw`; but the latter causes some flicker (with the
        # cursor, and in the statusline, tabline).
        #}}}
        var lnum = win_execute(preview_winid, searchcmd)->trim("\<c-j>")
        var showtag = 'norm! ' .. lnum .. 'G'
        win_execute(preview_winid, setsyntax + ['&l:cole = 3', showtag])

    elseif sourcetype == 'RecentFiles'
        # Why clearing the syntax first?{{{
        #
        # Suppose the previous file which was previewed was a Vim file.
        # A whole bunch of Vim syntax items are currently defined.
        #
        # Now, suppose  the current file which  is previewed is a  simple `.txt`
        # file; `do filetypedetect BufReadPost`  won't install new syntax items,
        # and won't  clear the  old ones;  IOW, your text  file will  be wrongly
        # highlighted with the Vim syntax.
        #}}}
        var setsyntax = ['syn clear | do filetypedetect BufReadPost ' .. fnameescape(filename)]
        win_execute(preview_winid, setsyntax + ['&l:cole = 3', 'norm! zR'])
    endif
enddef

def UpdateTitle() #{{{2
    # Special case:  no line matches what we've typed so far.
    if line('$', menu_winid) == 1 && winbufnr(menu_winid)->getbufline(1) == ['']
        # Warning: It's important that even if no line matches, the title still respects the format `12/34 (56)`.{{{
        #
        # Otherwise, after pressing `C-u`, the title will still not respect the format.
        # That's  also why  we don't  reset the  whole title.   We just  replace
        # `12/34` with `0/0`; this way, we can  be sure that any space used as a
        # padding is preserved.
        #}}}
        var newtitle = popup_getoptions(menu_winid).title
            ->substitute('\d\+/\d\+', '0/0', '')
        popup_setoptions(menu_winid, #{title: newtitle})
        return
    endif
    var newtitle = popup_getoptions(menu_winid).title
        ->substitute('\d\+', line('.', menu_winid), '')
        ->substitute('/\zs\d\+', line('$', menu_winid), '')
        ->substitute('(\zs\d\+\ze)', len(source), '')
    popup_setoptions(menu_winid, #{title: newtitle})
enddef

def ExitCallback(type: string, id: number, result: number) #{{{2
    # If we don't clear  the source now, next time we start  a fuzzy command, it
    # will keep looking in the same source, which might not be relevant anymore.
    source = []
    # Similarly, we need to  reset `filter_text` so that the next  time we run a
    # fuzzy  command, we  don't start  re-using the  same typed  text as  before
    # (which could  be completely irrelevant,  especially if we use  a different
    # command).
    filter_text = ''

    popup_close(preview_winid)
    # clear the message displayed at the command-line
    echo ''
    if result <= 0
        return
    endif
    try
        var chosen = filtered_source[result - 1].text
            ->split('\t')
            ->get(0, '')
            ->trim()
        if chosen == ''
            return
        endif
        if type == 'Help'
            exe 'h ' .. chosen
        elseif type == 'RecentFiles'
            exe 'sp ' .. chosen->fnameescape()
            norm! zv
        endif
    catch
        echohl ErrorMsg
        echom v:exception
        echohl NONE
    endtry
    # TODO: Could `source` increase Vim's memory footprint?  Should we unlet it now?{{{
    #
    # But even  if we want  to, we can't unlet  a script-local variable  in Vim9
    # script.  This begs another question; in  Vim9 script, is there a risk that
    # Vim's memory consumption increases when  we use a script-local variable as
    # a cache.
    #
    # Idea: Move `source` into a dictionary.
    # When you don't need it anymore, remove the key from the dictionary.
    #}}}
enddef
#}}}1
# Utility {{{1
def Permutations(l: list<string>): list<list<string>> #{{{2
# https://stackoverflow.com/a/17391851/9780968
    if len(l) == 0
        return [[]]
    endif
    var ret = []
    # iterate over the permutations of the sublist which excludes the first item
    for sublistPermutation in Permutations(l[1:])
    # iterate over the permutations of the original list
        for permutation in InsertItemAtAllPositions(l[0], sublistPermutation)
            ret += [permutation]
        endfor
    endfor
    return ret
enddef

def InsertItemAtAllPositions(item: string, l: list<string>): list<list<string>>
    var ret = []
    # iterate over all the positions at which we can insert the item in the list
    for i in range(len(l) + 1)
        ret += [ (i == 0 ? [] : l[0 : i - 1]) + [item] + l[i : ] ]
    endfor
    return ret
enddef

def BuflistedSorted(): list<string> #{{{2
    return getbufinfo(#{buflisted: true})
        ->filter({_, v -> getbufvar(v.bufnr, '&buftype', '') == ''})
        ->map({_, v -> #{bufnr: v.bufnr, lastused: v.lastused}})
        # the most recently active buffers first;
        # for 2 buffers accessed in the same second, the one with the bigger number first
        # (because it's the most recently created one)
        ->sort({i, j -> i.lastused < j.lastused ? 1 : i.lastused == j.lastused ? j.bufnr - i.bufnr : -1})
        ->map({_, v -> bufname(v.bufnr)})
enddef

def Uniq(list: list<string>): list<string> #{{{2
    var visited = {}
    var ret = []
    for path in list
        if !empty(path) && !has_key(visited, path)
            add(ret, path)
            visited[path] = 1
        endif
    endfor
    return ret
enddef

