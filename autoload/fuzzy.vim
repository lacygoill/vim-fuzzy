vim9script

# TODO: Feature request: a new builtin popup menu filter{{{
# which would be different than the existing one in 2 fundamental ways:
#
#    - it would cause Vim to automatically create an extra popup, below the popup
#      for which it filters the keypresses
#
#    - instead of receiving each keypress, the filter would receive the whole text
#      typed so far in the extra popup, but only when it has changed (i.e. it would
#      ignore motions)
#
# Could the extra  popup leverage the concept of  prompt buffer?  Alternatively,
# we could do without an extra popup,  and just rely on the command-line...  But
# it would be less  pretty (because the popup could be  far away), and confusing
# (what you  type is not an  Ex command, but  some arbitrary text which  a popup
# filter is going to process in some arbitrary way).
#
# ---
#
# With  our current  implementation,  which  relies on  a  simple `:echo`,  it's
# confusing when the cursor is in the middle of the popup.
#
# ---
#
# Our current simple  workaround (an `:echo`) does not  support complex editions
# (like `C-w`, `M-d`, ...) or motions  (like `M-b`, `C-a`, ...). Besides, it's a
# bit confusing because the cursor is not drawn next to what we're typing.
#}}}

if !executable('grep') || !executable('perl') || !executable('awk')
    echohl WarningMsg
    echom ':FuzzyHelp requires grep and perl/awk'
    echohl None
    finish
endif

prop_type_add('fuzzyhelp', #{highlight: 'Title'})

const TEXTWIDTH = 80
# 2 popups = 4 borders
const BORDERS = 4

var filter_text = ''
var preview_winid = 0
var tags_winid = 0

# What's the difference between `TAGLIST` and `filtered_taglist`?{{{
#
# The former is just the whole list of tag names.
# The latter is the filtered list matching  the pattern which the user has typed
# interactively at any given time.
#}}}
# TODO: There is some bug which prevents us from writing this:{{{
#
#     var TAGLIST: list<dict<string>>
#
# https://github.com/vim/vim/issues/7064
#}}}
var TAGLIST = []
var filtered_taglist: list<dict<string>>

# Interface {{{1
def fuzzy#help(pat_arg = '') #{{{2
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
        echo '[:FuzzyHelp] Not enough room'
        return
    endif

    var width = min([TEXTWIDTH, &columns - BORDERS])
    var line = &lines - &ch - statusline - height - 1

    filter_text = pat_arg
    var opts = #{
        line: line,
        col: (&columns - TEXTWIDTH - BORDERS) / 2,
        pos: 'topleft',
        maxheight: height,
        minheight: height,
        maxwidth: width,
        minwidth: width,
        # Set a title displaying some info about the numbers of tags we're dealing with.{{{
        #
        # Example:
        #
        #     12/34 (56)
        #     ├┘ ├┘  ├┘
        #     │  │   └ there were 56 help tags originally
        #     │  └ there are 34 help tags remaining
        #     └ we're selecting the 12th help tag
        #}}}
        title: ' 0/0 (0)',
        highlight: 'Normal',
        borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
        scrollbar: false,
        filter: FilterTags,
        callback: JumpToTag,
        }

    # create popup menu
    tags_winid = popup_menu('', opts)

    # create preview
    opts = popup_getoptions(tags_winid)
    extend(opts, #{line: opts.line - (height + BORDERS / 2)})
    remove(opts, 'callback')
    remove(opts, 'cursorline')
    remove(opts, 'filter')
    remove(opts, 'title')
    preview_winid = popup_create('', opts)

    if TAGLIST == []
        # if we've run `:FuzzyHelp` for the first time, we need to initialize `TAGLIST`
        InitTaglist()
    else
        # Otherwise, we just need to set the contents of the popup.
        # We can keep using  the same value for the taglist;  the one with which
        # it was  init the  last time.   Basically, `TAGLIST` can  be used  as a
        # cache now.
        UpdatePopup()
    endif
enddef
#}}}1
# Core {{{1
def InitTaglist() #{{{2
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
        out_cb: SetIntermediateTaglist,
        exit_cb: SetFinalTaglist,
        mode: 'raw',
        noblock: true,
        })
enddef

def SetIntermediateTaglist(_c: channel, data: string) #{{{2
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

    # turn the strings into dictionaries to easily ignore the filename later when filtering
    TAGLIST += splitted_data
        ->map({_, v -> split(v, '\t')})
        ->map({_, v -> #{text: v[0], aftertab: v[1]}})

    # need to be  set now, in case  we don't write any filtering  text, and just
    # press Enter  on whatever entry is  the first; otherwise, we  won't jump to
    # the right tag
    filtered_taglist = TAGLIST
        ->copy()
        ->filter({_, v -> v.text =~ filter_text})

    UpdatePopup()
enddef
var incomplete = ''

def SetFinalTaglist(...l: any) #{{{2
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
    TAGLIST += [#{text: parts[0], aftertab: parts[1]}]
    UpdatePopup()
enddef

def FilterTags(id: number, key: string): bool #{{{2
# Handle the keys typed in the popup menu.
# Narrow down the tag names based on the keys typed so far.

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

    # select a neighboring tag
    elseif index(["\<down>", "\<up>", "\<c-n>", "\<c-p>"], key) >= 0
        # No need to update the popup if we try to move beyond the first/last tag.{{{
        #
        # Besides, if  you let Vim  update the popup  in those cases,  it causes
        # some  annoying flickering  in the  popup title  when we  keep pressing
        # `C-n` or `C-p` for a bit too long.  Note that `id` (function argument)
        # and `tags_winid` (script local) have the same value.
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
        win_execute(preview_winid, 'setl cul | norm! j')
        return true
    elseif key == "\<m-k>" || key == "\<f22>"
        win_execute(preview_winid, 'setl cul | norm! k')
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
    # update only when we've  paused for at least 100ms; below  that, I doubt we
    # will notice the preview's contents not being updated
    if preview_timer > 0
        timer_stop(preview_timer)
        preview_timer = 0
    endif
    timer_start(100, {-> UpdatePreview()})

    UpdateTitle()
enddef
var preview_timer = 0

def UpdateMain() #{{{2
# update the popup with the new list of tag names
    var highlighted_lines: list<dict<any>>
    if filter_text =~ '\S'
        # Only fuzzy match against the tag name; not the filename.
        # Otherwise, we might get too many irrelevant results (test with the
        # pattern "changes").

        # We need to remove whitespace.{{{
        #
        # Suppose we're looking for `:h function-search-undo`.
        # We write `fun undo`; `matchfuzzy()` won't find anything because of
        # the space.
        #}}}
        # TODO: What if we type 2 (or more) keywords in the wrong order?{{{
        #
        # Suppose – again – we're looking for `:h function-search-undo`.
        # But this time, we type `undo fun`; `matchfuzzy()` won't find anything.
        # Ideally, we should:
        #
        #    - split `filtered_text` at each whitespace
        #    - generate all possible permutations of resulting tokens
        #    - run `matchfuzzy()` against each permutation
        #    - merge all the results
        #
        # This could take too much time if we write a lot of keywords.
        #
        #     a b c d e f g h i j k l
        #
        # 10 tokens; `10!` = `3628800` possible permuations.
        # I  guess  we  could limit  the  splitting  to  the  first 3  or  5
        # whitespace, to prevent an explosion of the permutations number.
        #}}}
        var str = substitute(filter_text, '\s*', '', 'g')
        var matchfuzzypos: list<list<any>> = matchfuzzypos(TAGLIST, str, #{key: 'text'})
        var pos: list<list<number>>
        # Why using `filtered_taglist` to save `matchfuzzypos()`?{{{
        #
        # It needs  to be updated  now, so  that `JumpToTag()` jumps  to the
        # right tag later.
        #}}}
        [filtered_taglist, pos] = matchfuzzypos

        # add info to get highlight via text properties
        highlighted_lines = filtered_taglist
            ->map({i, v -> #{
                text: v.text .. v.aftertab,
                props: map(pos[i], {_, w -> #{col: w + 1, length: 1, type: 'fuzzyhelp'}}),
                }})
    else
        highlighted_lines = TAGLIST
            ->copy()
            ->map({_, v -> #{
                text: v.text .. v.aftertab,
                props: [],
                }})
    endif
    popup_settext(tags_winid, highlighted_lines)
    # select first entry after every change of the filtering text (to mimic what fzf does)
    win_execute(tags_winid, 'norm! 1G')
    echo 'Help tag: ' .. filter_text
enddef

def UpdatePreview() #{{{2
    var matchlist = winbufnr(tags_winid)
        ->getbufline(line('.', tags_winid))
        ->matchlist('\(\S\+\)\s\+\(\S\+\)')
    if matchlist == []
        return
    endif
    var filename: string
    var tagname: string
    [tagname, filename] = matchlist[1:2]
    # Why passing "true, true" as argument to `globpath()`?{{{
    #
    # The  first  `true` can  be  useful  if  for  some reason  `'suffixes'`  or
    # `'wildignore'` are misconfigured.
    # The second  `true` is useful to  handle the case where  `globpath()` finds
    # several files.  It's easier to extract the first one from a list than from
    # a string.
    #}}}
    filename = globpath(&rtp, 'doc/' .. filename, true, true)->get(0, '')
    # Why this check?{{{
    #
    # We  might have  a stale  `tags`  file somewhere  in our  rtp, which  might
    # contain help tags which no longer exist.
    # It   happened   once   with    `~/.vim/doc/tags`   which   contained   the
    # `FastFold-commands` tag; the latter didn't exist anymore.
    #
    # When that happens, `readfile()` will raise `E484`.
    #
    #     E484: Can't open file <empty>
    #}}}
    if filename == ''
        return
    endif
    var text = readfile(filename)
    popup_settext(preview_winid, text)

    # highlight the text with the help syntax plugin
    var setsyntax = 'if get(b:, "current_syntax", "") != "help" | exe "do Syntax help" | endif'
    tagname = substitute(tagname, "'", "''", 'g')->escape('\')
    var searchcmd = printf("echo search('\\*\\V%s\\m\\*')", tagname)
    # Why not just running `search()`?{{{
    #
    # If you just run `search()`, Vim won't redraw the preview popup.
    # You'll need to run `:redraw`; but the latter causes some flicker (with the
    # cursor, and in the statusline, tabline).
    #}}}
    var lnum = win_execute(preview_winid, searchcmd)->trim("\<c-j>")
    var showtag = 'norm! ' .. lnum .. 'G'
    var cmd = [setsyntax, '&l:cole = 3', showtag]
    win_execute(preview_winid, cmd)
enddef

def UpdateTitle() #{{{2
    if line('$', tags_winid) == 1 && winbufnr(tags_winid)->getbufline(1) == ['']
        popup_setoptions(tags_winid, #{title: '0/0'})
        return
    endif
    var newtitle = popup_getoptions(tags_winid).title
        ->substitute('\d\+', line('.', tags_winid), '')
        ->substitute('/\zs\d\+', line('$', tags_winid), '')
        ->substitute('(\zs\d\+\ze)', len(TAGLIST), '')
    popup_setoptions(tags_winid, #{title: newtitle})
enddef

def JumpToTag(id: number, result: number) #{{{2
    popup_close(preview_winid)
    # clear the message displayed at the command-line
    echo ''
    if result <= 0
        return
    endif
    try
        var tagname = filtered_taglist[result - 1].text->matchstr('\S\+')
        exe 'h ' .. tagname
    catch
        echohl ErrorMsg
        echom v:exception
        echohl NONE
    endtry
    # TODO: Could `TAGLIST` increase Vim's memory footprint?  Should we unlet it now?{{{
    #
    # But even  if we want  to, we can't unlet  a script-local variable  in Vim9
    # script.  This begs another question; in  Vim9 script, is there a risk that
    # Vim's memory consumption increases when  we use a script-local variable as
    # a cache.
    #
    # Idea: Move `TAGLIST` into a dictionary.
    # When you don't need it anymore, remove the key from the dictionary.
    #}}}
enddef

