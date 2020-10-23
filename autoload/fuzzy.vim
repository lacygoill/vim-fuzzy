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

# TODO: Implement a mechanism which lets us mark multiple lines in the popup.
# Use the sign column to display a sign besides any marked line.

# TODO: Implement a  mechanism which  allows us  to run  arbitrary code  when we
# press another key then Enter to close the popup.
# For example,  if we press `C-q`,  we might want  all the selected lines  to be
# used to populate the qfl.
# Once done, post your solution here: <https://github.com/junegunn/fzf/issues/1885>

# TODO: Implement `:FuzzyGrep`.
# https://vi.stackexchange.com/questions/10692/how-to-interactively-search-grep-with-vim/10693#10693
#
#     $ grep -RHn '.*' .
#                      ^
#                      Vim's cwd

# TODO: Implement `:FuzzyLocate`.

# TODO: Implement `:FuzzyBuffer`.
# https://vi.stackexchange.com/questions/308/regex-that-prefers-shorter-matches-within-a-match-this-is-more-involved-than-n
# And maybe  `:FuzzyBuffers` (note the final  "s") to find some  needle in *all*
# the buffers.
#
# What about `:FzBuffers` which look for all opened buffers?

# TODO: Implement `:FuzzySnippets`.

# TODO: Get rid of the Vim plugins fzf and fzf.vim.{{{
#
# Get rid of their config in `~/.vim/plugin` and/or `~/.vim/after/plugin`.
# Get rid of anything we've written about these plugins in our notes.
# Update the `~/bin/up` script so that it updates the fzf binary.
#
# Update: Actually, there is still valuable code in there:
#
#     ~/.vim/plugin/fzf.vim
#     ~/.vim/autoload/plugin/fzf.vim
#
# And there are still some fzf commands we need to re-implement.
#
#     :FzRg (is it different than our future `:FuzzyGrep`?)
#     :FzFiles (is it different than our future `:FuzzyFiles`?)
#     :FzHistory:
#     :FzHistory/
#     ...
#
# What about this mapping:
#
#     nno <space>fm<esc> <nop>
#
# Will we still need it?
#
# Also, read `:h fzf-vim`.  Make sure  we don't lose any valuable feature before
# removing the plugins.
#}}}

const TEXTWIDTH = 80
# 2 popups = 4 borders
const BORDERS = 4

var filter_text = ''
var preview_winid = 0
var menu_winid = 0
var menu_buf = 0

var source: list<dict<string>>
var filtered_source: list<dict<string>>
var sourcetype: string

# Interface {{{1
def fuzzy#main(type: string) #{{{2
    sourcetype = type

    if UtilityIsMissing()
        return
    endif

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
        echom 'vim-fuzzy: Not enough room'
        echohl NONE
        return
    endif

    # Without this reset, we might wrongly re-use a stale source.{{{
    #
    #     $ cd && vim
    #     " press:  SPC ff C-c
    #     :cd /etc
    #     " press:  SPC ff
    #     " expected: the files of `/etc` are listed
    #     " actual: some of the files of the home directory are listed
    #}}}
    #   But we already invoke `Reset()` from `Clean()`, isn't that enough?{{{
    #
    # It's true  that we invoke  `Clean()` from `ExitCallback()`;  and `Clean()`
    # does indeed invoke `Reset()`.
    # However, when you  press exit the main popup before  the job has finished,
    # some of its callbacks can still be invoked and set `source`.
    #}}}
    # Make sure to reset as early as possible.{{{
    #
    # We need to reset other variables.
    # But  we don't  want to  accidentally reset  a variable  after it  has been
    # correctly initialized.
    #}}}
    Reset()

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
    menu_buf = winbufnr(menu_winid)
    prop_type_add('fuzzyMatch', #{bufnr: menu_buf, highlight: 'Title'})
    prop_type_add('fuzzyTrailing', #{bufnr: menu_buf, highlight: 'Comment'})

    # create preview
    opts = popup_getoptions(menu_winid)
    extend(opts, #{line: opts.line - (height + BORDERS / 2)})
    remove(opts, 'callback')
    remove(opts, 'cursorline')
    remove(opts, 'filter')
    remove(opts, 'title')
    preview_winid = popup_create('', opts)

    InitSource()
enddef
#}}}1
# Core {{{1
def InitSource() #{{{2
    if sourcetype == 'Commands' || sourcetype =~ '^Mappings'
        InitCommandsOrMappings()
    elseif sourcetype == 'Files'
        InitFiles()
    elseif sourcetype == 'HelpTags'
        InitHelpTags()
    elseif sourcetype == 'RecentFiles'
        InitRecentFiles()
    endif

    UpdatePopups()
enddef

def InitCommandsOrMappings() #{{{2
    var cmd: string
    var relevant: string
    var noise: string
    if sourcetype == 'Commands'
        cmd = 'verb com'
        # The first 4 characters are used for flags, and what comes after the newline is irrelevant.{{{
        #
        #     !"b|SomeCmd ...
        #     ^--^
        #}}}
        relevant = '....\zs[^\n]*'
        # We're only interested in the command name and its definition; all the other fields are noise.{{{
        #
        #     SomeCmd    ?    .  win    customlist    ...
        #                │    ├────┘    ├────────┘
        #                │    │         └ Complete
        #                │    └ Address
        #                └ Args
        #}}}
        noise = '^\S*\zs.*\ze\%43c.*'
    elseif sourcetype =~ '^Mappings'
        cmd = 'verb ' .. sourcetype[-2:-2]->tolower() .. 'map'
        # The first 3 characters are used for the mode.{{{
        #
        #     nox<key> ...
        #     ^^^
        #}}}
        relevant = '...\zs[^\n]*'
        # Some flags might be present.{{{
        #
        #     x  =rd         *@:RefDot<CR>
        #                    ^^
        #                    noise
        #}}}
        noise = '^\S*\s\+\zs[*&]\=[@ ]\='
    endif
    source = execute(cmd)
        # remove first empty lines
        ->substitute('^\%(\s*\n\)*', '', '')
        # split after every "Last set from ..." line
        ->split('\n\s*Last set from [^\n]* line \d\+\zs\n')
        # transforms each pair of lines into a dictionary
        ->map({_, v -> #{
            text: matchstr(v, relevant)->substitute(noise, '', ''),
            # `matchstr()` extracts the filename.{{{
            #
            #     Last set from /path/to/script.vim line 123
            #                            ^--------^
            #
            # And `substitute()` replaces ` line 123` into `:123`.
            #}}}
            trailing: matchstr(v, '/\zs[^/\\]*$')->substitute(' [^ ]* ', ':', ''),
            # Don't invoke `ExpandTilde()` right now; it might be a little costly.{{{
            #
            # It was too costly in the past when we used `expand()`.  Now we use
            # `ExpandTilde()`, which relies on  `substitute()` and is faster, so
            # I don't know whether it would be still too costly...
            #}}}
            location: matchstr(v, 'Last set from .* line \d\+$'),
            }})

    if sourcetype == 'Commands'
        # Remove heading:{{{
        #
        #     Name              Args Address Complete    Definition
        #}}}
        remove(source, 0)
    endif

    # align all the names of commands/mappings in a field (max 35 cells)
    var longest_name = source
        ->copy()
        ->map({_, v -> v.text->matchstr('^\S*')->strchars(true)})
        ->max()
    longest_name = min([35, longest_name])
    source->map({_, v -> extend(v, #{
        text: matchstr(v.text, '^\S*')->printf('%-' .. longest_name .. 'S')
            .. ' ' .. matchstr(v.text, '^\S*\s\+\zs.*')
        })})
enddef

def InitFiles() #{{{2
    # TODO: Our code is still a bit too slow for an interactive usage.{{{
    #
    # Take inspiration from the `fileselect` plugin.
    #
    # The rest of the  comment is stale, but some of its  idea(s) might still be
    # useful in the future.
    #
    #     It doesn't use a  job to get the list of files.   It runs `readdirex()` on
    #     the cwd and each of its subdirectories.   But that might take a long time.
    #     So, it uses 2  loops: a `while` loop, and a `for`  loop.  The `while` loop
    #     makes sure that the function  calling `readdirex()` doesn't block Vim more
    #     than 0.1s  (presumably because it  would be noticeable  by the user  if it
    #     went beyond).  The `for` loop iterates over the entries of a directory.
    #
    #     We could do sth similar.
    #     We could cut  the source into smaller chunks (50000  entries?), and invoke
    #     `UpdateMainText()` on  each chunk.  Between  each chunk, we would  let Vim
    #     "breathe" during half  a second.  After that half a  second, a timer would
    #     reinvoke `UpdateMainText()` for the next  chunk.  The process would repeat
    #     itself until there are no more chunks.
    #
    #     Update: The waiting time could be rather short (`.1s`?), and each time the
    #     callback is  invoked it  would check whether  we've typed  something (i.e.
    #     whether `filter_text` has changed).  If so, it would bail out, and restart
    #     a new  timer.  The callback  would run its code  only if nothing  has been
    #     typed.
    #
    #     Update: I  think you'll  need 2  new variables.   One which  remembers the
    #     number of  lines you've already  filtered so far.   The other should  be a
    #     flag telling us whether the filter text has changed since the last time we
    #     filtered a chunk of the source.
    #}}}
    var findcmd = GetFindCmd()
    # How slow is `find(1)`?{{{
    #
    # As  an example,  currently, `find(1)`  finds  around 300K  entries in  our
    # `$HOME`.  It needs around 5s:
    #
    #     $ find ... | wc -l
    #
    # Note  that –  when testing  –  it's important  to redirect  the output  of
    # `find(1)` to something  else than the terminal; hence the  pipe to `wc -l`
    # in the previous command.
    # The terminal  would add some overhead  to regularly update the  screen and
    # show `find(1)`'s  output.  Besides,  most (all?)  terminals can't  keep up
    # with a command which has a fast output;  i.e. they need to drop *a lot* of
    # lines when displaying the output.
    #}}}
    myjob = job_start(['/bin/sh', '-c', findcmd], #{
        out_cb: SetIntermediateSource,
        exit_cb: SetFinalSource,
        mode: 'raw',
        noblock: true,
        })
enddef

var myjob: job

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

def InitRecentFiles() #{{{2
    var recentfiles: list<string> = BuflistedSorted()
        + copy(v:oldfiles)->filter({_, v -> ExpandTilde(v)->filereadable()})
    map(recentfiles, {_, v -> fnamemodify(v, ':p')})
    var curbuf = expand('%:p')
    source = recentfiles
        ->filter({_, v -> v != '' && v != curbuf && !isdirectory(v)})
        ->Uniq()
        ->map({_, v -> #{text: fnamemodify(v, ':~:.'), trailing: '', location: ''}})
enddef

def SetIntermediateSource(_c: channel, data: string) #{{{2
    job_is_running = true
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
    if sourcetype == 'Files'
        source += splitted_data
            ->map({_, v -> #{text: v, trailing: '', location: ''}})
    else
        source += splitted_data
            ->map({_, v -> split(v, '\t')})
            ->map({_, v -> #{text: v[0], trailing: v[1], location: ''}})
    endif

    UpdatePopups()
enddef

var incomplete = ''
var job_is_running = false

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
    if sourcetype == 'Files'
        source += [#{text: parts->join("\t")->trim("\<c-j>"), trailing: '', location: ''}]
    else
        source += [#{text: parts[0], trailing: parts[1]->trim("\<c-j>"), location: ''}]
        #                                                     ^------^
        #                        the last line of the shell ouput ends
        #                        with an undesirable trailing newline
    endif

    UpdatePopups()
    job_is_running = false
enddef

def FilterLines(id: number, key: string): bool #{{{2
# Handle the keys typed in the popup menu.
# Narrow down the lines based on the keys typed so far.

    # filter the names based on the typed key and keys typed before
    if key =~ '^\p$'
        filter_text ..= key
        UpdatePopups()
        return true

    # clear the filter text entirely
    elseif key == "\<c-u>"
        filter_text = ''
        UpdatePopups()
        return true

    # erase only one character from the filter text
    elseif key == "\<bs>" || key == "\<c-h>"
        if len(filter_text) >= 1
            filter_text = filter_text[:-2]
            UpdatePopups()
        endif
        return true

    # select a neighboring line
    elseif index(["\<down>", "\<up>", "\<c-n>", "\<c-p>"], key) >= 0
        var curline = line('.', id)
        var lastline = line('$', id)
        # No need to update the popup if we try to move beyond the first/last line.{{{
        #
        # Besides, if  you let Vim  update the popup  in those cases,  it causes
        # some  annoying flickering  in the  popup title  when we  keep pressing
        # `C-n` or `C-p` for a bit too long.  Note that `id` (function argument)
        # and `menu_winid` (script local) have the same value.
        #}}}
        if index(["\<up>", "\<c-p>"], key) >= 0 && curline == 1
        || index(["\<down>", "\<c-n>"], key) >= 0 && curline == lastline
            return true
        endif
        var cmd = 'norm! ' .. (key == "\<c-n>" || key == "\<down>" ? 'j' : 'k')
        win_execute(id, cmd)
        UpdatePopups(true)
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

def UpdatePopups(notTheMainText = false) #{{{2
    if !notTheMainText
        UpdateMainText()
    endif

    UpdateMainTitle()

    # no need to  update the preview on every keypress,  when we're typing fast;
    # update only when we've paused for at least 50ms
    if preview_timer > 0
        timer_stop(preview_timer)
        preview_timer = 0
    endif
    preview_timer = timer_start(50, UpdatePreview)
enddef

var preview_timer = 0

def UpdateMainText() #{{{2
# update the popup with the new list of lines

    var to_filter: list<dict<string>>
    if job_is_running
        if filter_text != last_filter_text
            last_filtered_line = 0
            popup_settext(menu_winid, '')
            last_filter_text = filter_text
        endif
        to_filter = source[last_filtered_line : ]
        last_filtered_line = len(source)
    else
        to_filter = source
    endif

    var highlighted_lines: list<dict<any>>
    if filter_text =~ '\S'
        var matchfuzzypos = matchfuzzypos(to_filter, filter_text, #{key: 'text'})
        var pos: list<list<number>>
        # Why using `filtered_source` to save `matchfuzzypos()`?{{{
        #
        # It needs to be updated now, so that `ExitCallback()` works as expected
        # later (e.g. to jump to the right help tag).
        #}}}
        [filtered_source, pos] = matchfuzzypos

        # add info to get highlight via text properties
        highlighted_lines = filtered_source
            ->map({i, v -> #{
                text: v.text .. "\t" .. v.trailing,
                props: map(pos[i], {_, w -> #{col: w + 1, length: 1, type: 'fuzzyMatch'}})
                    + [#{col: v.text->strlen() + 1, end_col: 999, type: 'fuzzyTrailing'}],
                location: v.location,
                }})
    else
        highlighted_lines = to_filter
            ->copy()
            ->map({_, v -> #{
                text: v.text .. "\t" .. v.trailing,
                props: [#{col: v.text->strlen() + 1, end_col: 999, type: 'fuzzyTrailing'}],
                location: v.location,
                }})
    endif

    # `!job_is_running` for when we type some characters to filter the menu.
    # TODO:  I'm not convinced `!job_is_running`  is always correct.  What if:{{{
    #
    #    - we have a huge source obtained synchronously
    #    - we refactor the code to split the source into smaller chunks
    #    - we invoke the current function several times on each chunk
    #
    # We will then  need to *append*  lines; not reset the whole buffer.
    # I think you'll need to write sth like this:
    #
    #     if !Menu_is_empty() && (job_is_running || processing_big_source)
    #         Popup_appendtext(highlighted_lines)
    #     else
    #         popup_settext(menu_winid, highlighted_lines)
    #     endif
    #
    # `processing_big_source` is  a boolean flag  which should be on  when we're
    # processing a big source.
    #
    # Update: I'm still not sure this pseudo-code is correct.
    #}}}
    if Menu_is_empty() || !job_is_running
        popup_settext(menu_winid, highlighted_lines)
    else
        Popup_appendtext(highlighted_lines)
    endif
    # select first entry after every change of the filtering text (to mimic what fzf does)
    win_execute(menu_winid, 'norm! 1G')

    echohl ModeMsg
    echo sourcetype->substitute('\l\zs\ze\u', ' ', 'g') .. ': '
    echohl Title
    echon filter_text
    echohl NONE
enddef

var last_filtered_line: number
var last_filter_text: string

def UpdateMainTitle() #{{{2
    # Special case:  no line matches what we've typed so far.
    if line('$', menu_winid) == 1 && getbufline(menu_buf, 1) == ['']
        # Warning: It's important that even if no line matches, the title still respects the format `12/34 (56)`.{{{
        #
        # Otherwise, after pressing `C-u`, the title will still not respect the format.
        # That's  also why  we don't  reset the  whole title.   We just  replace
        # `12/34` with `0/0`; this way, we can  be sure that any space used as a
        # padding is preserved.
        #}}}
        var newtitle = popup_getoptions(menu_winid)
            ->get('title', '')
            ->substitute('\d\+/\d\+', '0/0', '')
        popup_setoptions(menu_winid, #{title: newtitle})
        return
    endif
    var newtitle = popup_getoptions(menu_winid)
        ->get('title', '')
        ->substitute('\d\+', line('.', menu_winid), '')
        ->substitute('/\zs\d\+', line('$', menu_winid), '')
        ->substitute('(\zs\d\+\ze)', len(source), '')
    popup_setoptions(menu_winid, #{title: newtitle})
enddef

def UpdatePreview(timerid = 0) #{{{2
    var line = getbufline(menu_buf, line('.', menu_winid))

    # clear the preview if nothing matches the filtering pattern
    if line == ['']
        popup_settext(preview_winid, '')
        return
    endif

    var splitted = line
        ->get(0, '')
        ->split('\t\+')
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
    var lnum: string
    if sourcetype == 'HelpTags'
        # Why passing "true, true" as argument to `globpath()`?{{{
        #
        # The  first  `true` can  be  useful  if  for  some reason  `'suffixes'`  or
        # `'wildignore'` are misconfigured.
        # The second  `true` is useful to  handle the case where  `globpath()` finds
        # several files.  It's easier to extract the first one from a list than from
        # a string.
        #}}}
        filename = globpath(&rtp, 'doc/' .. right, true, true)->get(0, '')
    elseif sourcetype == 'Files' || sourcetype == 'RecentFiles'
        filename = ExpandTilde(left)->fnamemodify(':p')
    elseif sourcetype == 'Commands' || sourcetype =~ '^Mappings'
        var matchlist = (filtered_source ?? source)
            ->get(line('.', menu_winid) - 1, {})
            ->get('location', '')
            ->matchlist('Last set from \(.*\) line \(\d\+\)$')
        if len(matchlist) < 3
            return
        endif
        [filename, lnum] = matchlist[1:2]
        filename = ExpandTilde(filename)
    endif
    if !filereadable(filename)
        return
    endif

    var text = readfile(filename)
    popup_settext(preview_winid, text)
    # TODO: The preview window's title should  display the path to the previewed
    # file (at least for mappings; not sure about the other types of sources).

    def Prettify()
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
        var setsyntax = 'syn clear | do filetypedetect BufReadPost ' .. fnameescape(filename)
        var fullconceal = '&l:cole = 3'
        var unfold = 'norm! zR'
        var whereAmI = sourcetype == 'Commands' || sourcetype =~ '^Mappings' ? '&l:cul = 1' : ''
        win_execute(preview_winid, [setsyntax, fullconceal, unfold, whereAmI])
    enddef

    # syntax highlight the text and make sure the cursor is at the relevant location
    if sourcetype == 'HelpTags'
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
        lnum = win_execute(preview_winid, searchcmd)->trim("\<c-j>")
        var showtag = 'norm! ' .. lnum .. 'G'
        win_execute(preview_winid, setsyntax + ['&l:cole = 3', showtag])

    elseif sourcetype == 'Commands' || sourcetype =~ '^Mappings'
        win_execute(preview_winid, 'norm! ' .. lnum .. 'Gzz')
        Prettify()

    elseif sourcetype == 'Files' || sourcetype == 'RecentFiles'
        Prettify()
    endif
enddef

def ExitCallback(type: string, id: number, result: number) #{{{2
    if result <= 0
        # If a job  has been started, and  we want to kill it  by pressing `C-c`
        # because  it takes  too much  time, `job_stop()`  must be  invoked here
        # (which `Clean()` does).
        Clean()
        return
    endif

    try
        var chosen = (filtered_source ?? source)
            ->get(result - 1, {})
            ->get('text', '')
            ->split('\t')
            ->get(0, '')
            ->trim()
        if chosen == ''
            return
        endif

        # The cursor is wrongly moved 1 line down when I press Enter!{{{
        #
        # Maybe an error  is raised somewhere (not necessarily  from the current
        # function; it could be due to a triggered autocmd defined elsewhere).
        # And if an error is raised, `Enter` is not discarded.
        # From `:h popup-filter-errors`:
        #
        #    > If the filter causes an error then it is assumed to return zero.
        #
        # See also:
        # https://github.com/vim/vim/issues/7156#issuecomment-713527749
        #
        # One solution  is to make sure  that the error is  either suppressed by
        # `:silent!` or caught by a try conditional.
        # Unfortunately, this only works in Vim script legacy, not in Vim9.
        # So, if:
        #
        #    - the current function fires an event
        #    - the event triggers an autocmd
        #    - the autocmd calls a legacy function
        #    - the legacy function executes a command which raises an error
        #
        # `Enter` won't be discarded; even if the error is suppressed or caught.
        # But I *think* it will be fixed in the future.
        #
        # See also:
        # https://github.com/vim/vim/issues/7178#issuecomment-714442958
        #}}}
        if type == 'Files' || type == 'RecentFiles'
            exe 'sp ' .. chosen->fnameescape()

        elseif type == 'HelpTags'
            exe 'h ' .. chosen

        elseif type == 'Commands' || type =~ '^Mappings'
            var matchlist = get(filtered_source ?? source, result - 1, {})
                ->get('location')
                ->matchlist('Last set from \(.*\) line \(\d\+\)$')
            if len(matchlist) < 3
                return
            endif
            var filename: string
            var lnum: string
            [filename, lnum] = matchlist[1:2]
            exe 'sp ' .. filename
            exe 'norm! ' .. lnum .. 'G'
        endif
        norm! zv
    catch
        echohl ErrorMsg
        echom v:exception
        echohl NONE
    finally
        Clean()
    endtry
enddef
#}}}1
# Utility {{{1
def UtilityIsMissing(): bool #{{{2
    if sourcetype == 'HelpTags'
        if !executable('grep') || (!executable('perl') && !executable('awk'))
            Error('Require grep and perl/awk')
            return true
        endif
    elseif sourcetype == 'Files'
        if !executable('find')
            Error('Require find')
            return true
        endif
    endif
    return false
enddef

def Error(msg: string) #{{{2
    echohl ErrorMsg
    echom msg
    echohl None
enddef

def BuflistedSorted(): list<string> #{{{2
    # Note: You could also use `undotree()` instead of `lastused`.{{{
    #
    # The maximal precision of `lastused` is only 1s.
    # `undotree()` has a much better precision, but the semantics of the sorting
    # would change; i.e. the sorting would no longer be based on the last time a buffer
    # was active, but on the last time it was changed.
    #}}}
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

def Popup_appendtext(text: list<dict<any>>) #{{{2
    var lastlnum = line('$', menu_winid)

    # append text
    eval text
        ->copy()
        ->map({_, v -> v.text})
        ->appendbufline(menu_buf, '$')

    # apply text properties
    # Can't use a nested `map()` because nested closures don't always work.{{{
    #
    #     eval text
    #         ->map({i, v -> v.props->map({_, w -> call('prop_add',
    #             [lastlnum + i + 1, w.col] + [extend(w, #{bufnr: menu_buf})])})})
    #
    # Here, `lastlnum` would always be – wrongly – evaluated to `1`.
    #
    # This is a known limitation: https://github.com/vim/vim/issues/7150
    # It could be fixed one day, but I still prefer a `for` loop:
    #
    #    - it makes the code a little more readable
    #    - it might be faster
    #}}}
    var i = 0
    for d in text
        eval d.props
            ->map({_, v -> call('prop_add',
                [lastlnum + i + 1, v.col] + [extend(v, #{bufnr: menu_buf})])})
        i += 1
    endfor
enddef

def Clean(closemenu = false) #{{{2
    # the job  makes certain assumptions  (like the existence of  popups); let's
    # stop it  first, to avoid  any issue if we  break one of  these assumptions
    # later
    var job_was_running = false
    if job_status(myjob) == 'run'
        job_was_running = true
        job_stop(myjob)
    endif

    popup_close(preview_winid)
    if closemenu
        popup_close(menu_winid)
    endif

    # clear the message displayed at the command-line
    echo ''
    # TODO: We need this in case we exit the popup while a job is still running.{{{
    #
    # Otherwise, some job's callbacks might still  be invoked even after the job
    # has been stopped.  They might call:
    #
    #     UpdatePopups() → UpdateMainText() → Popup_appendtext()
    #
    # The latter function assumes that `menu_buf` refers to an existing buffer.
    #
    # However, all  of this looks  ugly; the  job's callbacks should  not invoke
    # `UpdatePopups()`.  At least, they should not do it unconditionally.
    # We'll refactor how the popup is updated in the future.
    # When you're done  with this refactoring, check whether we  still need this
    # `sleep` and this `job_was_running`.
    # To do a test, enter a directory  with a lot of files (e.g. `$HOME`), press
    # `SPC ff`, then `ESC`.
    #}}}
    if job_was_running
        sleep 1m
    endif
    # since this might break some assumptions in our code, let's keep it at the end
    Reset()
enddef

def GetFindCmd(): string #{{{2
    # split before any comma which is not preceded by an odd number of backslashes
    var tokens = split(&wig, '\%(\\\@<!\\\%(\\\\\)*\\\@!\)\@<!,')

    # ignore files whose name is present in `'wildignore'` (e.g. `tags`)
    var by_name = tokens
        ->copy()
        ->filter({_, v -> v !~ '[/*]'})
        ->map({_, v -> '-iname ' .. shellescape(v) .. ' -o'})
        ->join()

    # ignore files whose extension is present in `'wildignore'` (e.g. `*.mp3`)
    var by_extension = tokens
        ->copy()
        ->filter({_, v -> v =~ '\*' && v !~ '/'})
        ->map({_, v -> '-iname ' .. shellescape(v) .. ' -o'})
        ->join()

    # ignore files whose directory is present in `'wildignore'` (e.g. `*/build/*`)
    # How does `-prune` work?{{{
    #
    # When the  path of a file  matches the glob preceding  `-prune`, the latter
    # returns true; as  a result, the rhs  is not evaluated.  But  when the path
    # does not match,  `-prune` returns false, and the rhs  *is* evaluated.  See
    # `man find /^EXAMPLES/;/construct`.
    #}}}
    var cwd = getcwd()
    var by_directory = tokens
        ->copy()
        ->filter({_, v -> v =~ '/'})
        ->map({_, v -> '-ipath '
            # Why replacing the current working directory with a dot?{{{
            #
            #     $ mkdir -p /tmp/test \
            #         && cd /tmp/test \
            #         && touch file{1..3} \
            #         && mkdir ignore \
            #         && touch ignore/file{1..3}
            #
            #                          ✘
            #                      v-------v
            #     $ find . -ipath '/tmp/test/ignore/*' -o -type f -print
            #     ./file2~
            #     ./file1~
            #     ./ignore/file2~
            #     ./ignore/file1~
            #     ./ignore/file3~
            #     ./file3~
            #
            #                      ✔
            #                      v
            #     $ find . -ipath './ignore/*' -o -type f -print
            #     ./file2~
            #     ./file1~
            #     ./file3~
            #}}}
            .. substitute(v, '^\V' .. cwd->escape('\') .. '/', './', '')->shellescape()
            .. ' -prune -o'})
        ->join()

    var hidden_files = '-path ''*/.*'' -prune'
    return printf('find . %s %s %s %s -o -type f -print',
        by_name, by_extension, by_directory, hidden_files)
enddef

def ExpandTilde(path: string): string #{{{2
    # Why don't you simply use `expand()`?{{{
    #
    # It expands too much, and might raise unexpected errors.
    # For example:
    #
    #     echo expand('~/[a-1]/file.txt')
    #     E944: Reverse range in character class~
    #
    # Even though  `[a-1]` is an ugly  directory name, it's still  valid, and no
    # error should be raised.
    #}}}
    return substitute(path, '^\~/', $HOME .. '/', '')
enddef

def Reset() #{{{2
    menu_buf = 0
    source = []
    filtered_source = []
    filter_text = ''
    incomplete = ''
    job_is_running = false
    last_filtered_line = 0
    last_filter_text = ''
enddef

def Menu_is_empty(): bool #{{{2
    return line('$', menu_winid) == 1 && getbufline(menu_buf, 1) == ['']
enddef

