vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

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
# Maybe the extra popup could leverage the concept of prompt buffer.
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
# It has been acknowledged in the todo list.  From `:h todo /^Popup`:
#
#    > Popup windows:
#    > - Add a flag to make a popup window focusable?
#
# You could wait for this todo item  to be implemented, and test whether you can
# use the new feature to get an editable prompt.
#}}}

# TODO: Implement an hourglass-like  indicator in the popup's  title.  You can't
# rely  on the  numbers growing  in the  title.  Vim  might be  still processing
# without any number growing.  Or the numbers could be growing erratically.  For
# example, right now, if we use  `Locate`, and type `foobarbaz`, right after the
# `z` is inserted, there is an unusal long  time for the title to go from `1/16`
# to the final `1/32`.  We need a more predictable indicator.

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

# TODO: Implement `:Snippets`.
#
#     echo UltiSnips#SnippetsInCurrentScope()

# TODO: Implement a mechanism which lets us mark multiple lines in the popup.
# Use the sign column to display a sign besides any marked line.

# TODO: In the filter popup, if `C-q` is pressed, exit and populate the qfl with
# all the selected lines.

# TODO: Implement `:FzBLines` (lines in the current buffer).{{{
#
# And maybe `:Lines` to find some needle in *all* the buffers.
#
# ---
#
# This  is an  example of  source  which can  be  huge, but  cannot be  obtained
# asynchronously.  This is an issue, because it can block Vim for a long time.
# Check out how `vim-fileselect` tackle this issue.
#}}}
# TODO: Implement `:FzUnichar`.{{{
#
# Check out `unichar#complete#fuzzy()`.
# Or maybe we should just invoke `fuzzy#main()` from `vim-unichar`?
#}}}
# TODO: Implement `:FzCommits`; git commits.
# TODO: Implement `:FzBCommits`; git commits for the current buffer.
# TODO: Implement `:FzBTags`; tags in the current buffer.
# TODO: Implement `:FzBuffers`; open buffers.
# TODO: Implement `:FzGFiles?`; git files; `git status`.
# TODO: Implement `:FzGFiles`; git files; `git ls-files`.
# TODO: Implement `:FzHighlight`; highlight groups.
# TODO: Implement `:FzMan`; man pages.
# TODO: Implement `:FzMarks`.
# TODO: Implement `:FzRecentExCommands`.
# TODO: Implement `:FzRecentSearchCommands`.
# TODO: Implement `:FzTags`; tags in the project.
# TODO: Implement `:FzWindows`; open windows.
# TODO: Should we use `delta(1)` for `:FzCommits`, `:FzBCommits`, `FzGFiles?` to format git's output?
# If interested, see how `fzf.vim` does it.

# TODO: Sometimes `Locate` is much slower than usual (from 8s to ≈ 45s).
# And sometimes, `$ locate /` is much slower than usual (from .5s to 4s).
# What's going on?
# And btw, why is `Locate` so slow compared to `locate(1)`?
# I don't think `Files` is that slow compared to `find(1)`.
# Is it because `Locate` finds much more files?

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

# Config {{{1

# 2 popups = 4 borders
const BORDERS: number = 4

# when filtering, ignore matches with a  too low score (the lower this variable,
# the more matches, but also the more irrelevant some of them might be)
# How to find a good value?{{{
#
# Try to compare the results with `fzf(1)`.
# For example, you could dump the normal mappings table in a file, and pass it to `fzf(1)`:
#
#     $ cat /tmp/dump | fzf
#
# Type some filtering text, and compare  the number of remaining entries to what
# you  get in  Vim.  Decrease  `MIN_SCORE`  if you  think you  don't get  enough
# matches; increase it if you think you get too many matches.
#}}}
const MIN_SCORE = 70

# There is no need to display *all* the filtered lines in the popup.{{{
#
# Suppose 10000 lines match your filter text; are you really going to select the
# 5000th one?   Of course not.  You're  going to type more  characters to filter
# out more lines, until the one you're looking for is visible.
#
# Why?  Because moving to  the 5000th one is stupidly slow,  and the whole point
# of this plugin  is to save time.  To  give you an idea, it takes  about 25s to
# select the 1000th entry.  That's already too much.  Note that our popup filter
# lets us  jump to the  end by  pressing `C-g`, so  in practice, the line which
# is needs the most time to be selected is the 500th one, not the 1000th one.
# You'll need approximately 12s to reach it, which looks reasonable.
#
# ---
#
# Limiting the number of lines in the popup menu is also a useful optimization.
# For example, if  the popup contains more  than a million lines,  and you start
# typing your filter text, Vim will need a few seconds just to reset the popup:
#
#     popup_settext(menu_winid, '')
#
# There's not much we  can do to optimize that, except for  limiting the size of
# the popup menu.
#}}}
const POPUP_MAXLINES: number = 100

const PREVIEW_MAXSIZE: float = 5 * pow(2, 20)

# Maximum number of lines we're ok for `matchfuzzypos()` to process.{{{
#
# We don't want `matchfuzzypos()` to process  too many lines at once, because it
# might be  slow and block Vim,  while we want  to add some character(s)  to the
# filter text.
#
# Note that `matchfuzzypos()` is followed  by a `map()` invocation whose purpose
# is to add some  highlighting.  Same issue: it might be too  slow if the source
# is huge.
#
# If  the source  is bigger  than this  constant, our  code will  split it  into
# smaller chunks, which will be processed one after the other, via timers.
# These  timers   will  let  us  type   text  if  needed  while   the  soure  is
# being  processed;  in  effect,  this  should give  us  the  *impression*  that
# `matchfuzzypos()` is run asynchronously.
#}}}
# Don't reduce this setting too much.{{{
#
# The lower it is, the harder it is  to type our filtering text; some typed keys
# get dropped.  Empirically, it seems that you can go down to 4'000.
#}}}
const SOURCE_CHUNKSIZE: number = 10'000

const TEXTWIDTH: number = 80

# if we get an absurdly huge source, we should bail out
const TOO_BIG = 2'000'000

const UPDATEPREVIEW_WAITINGTIME: number = 50

# Init {{{1

var filter_text: string = ''
var filtered_source: list<dict<any>>
var incomplete: string = ''
var last_filter_text: string = ''
var last_filtered_line: number = -1
var last_source_length: number = -1
var menu_buf: number = -1
var menu_winid: number = -1
var moving_in_popup: bool
var moving_in_popup_timer: number = -1
var myjob: job
var new_last_filtered_line: number = -1
var popup_width: number
var popups_update_timer: number = -1
var preview_timer: number = -1
var preview_winid: number = -1
var source: list<dict<string>>
var source_is_being_computed: bool = false
var sourcetype: string

# Interface {{{1
def fuzzy#main(type: string) #{{{2
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

    sourcetype = type

    if UtilityIsMissing()
        return
    endif

    var height: number = &lines / 3
    var statusline: number = (&ls == 2 || &ls == 1 && winnr('$') >= 2) ? 1 : 0
    var tabline: number = (&stal == 2 || &stal == 1 && tabpagenr('$') >= 2) ? 1 : 0
    def Offset(): number
        var offset: number = 0
        var necessary: number = 2 * height + BORDERS
        var available: number = &lines - &ch - statusline - tabline
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

    popup_width = min([TEXTWIDTH, &columns - BORDERS])
    var line: number = &lines - &ch - statusline - height - 1

    var opts: dict<any> = {
        line: line,
        col: (&columns - TEXTWIDTH - BORDERS) / 2,
        pos: 'topleft',
        maxheight: height,
        minheight: height,
        maxwidth: popup_width,
        minwidth: popup_width,
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
        filter: PopupFilter,
        callback: function(ExitCallback, [sourcetype]),
        }

    # create popup menu
    menu_winid = popup_menu('', opts)
    menu_buf = winbufnr(menu_winid)
    prop_type_add('fuzzyMatch', {bufnr: menu_buf, highlight: 'Title'})
    prop_type_add('fuzzyHeader', {bufnr: menu_buf, highlight: 'Comment'})
    prop_type_add('fuzzyTrailer', {bufnr: menu_buf, highlight: 'Comment'})

    # create preview
    opts = popup_getoptions(menu_winid)
    opts.line = opts.line - (height + BORDERS / 2)
    remove(opts, 'callback')
    remove(opts, 'cursorline')
    remove(opts, 'filter')
    remove(opts, 'title')
    preview_winid = popup_create('', opts)

    InitSource()
    UpdatePopups()
enddef
#}}}1
# Core {{{1
def InitSource() #{{{2
    if sourcetype == 'Commands' || sourcetype =~ '^Mappings'
        InitCommandsOrMappings()

    elseif sourcetype == 'Files'
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
        GetFindCmd()->Job_start()

    elseif sourcetype == 'Grep'
        # You shouldn't need to pass any option to `rg(1)`.{{{
        #
        # Unless you want something special.
        # General settings should be written in: `~/.config/ripgreprc`.
        #}}}
        var cmd: string = executable('rg') ? "rg '.*' ." : 'grep -RHIins'
        Job_start(cmd)

    elseif sourcetype == 'HelpTags'
        InitHelpTags()

    elseif sourcetype == 'Locate'
        Job_start('locate /')

    elseif sourcetype == 'RecentFiles'
        InitRecentFiles()

    elseif sourcetype =~ '^Registers'
        InitRegisters()
    endif

    BailOutIfTooBig()
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
        cmd = 'verb ' .. sourcetype[-2]->tolower() .. 'map'
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
        # transform each pair of lines into a dictionary
        ->mapnew((_, v) => ({
            text: matchstr(v, relevant)->substitute(noise, '', ''),
            # `matchstr()` extracts the filename.{{{
            #
            #     Last set from /path/to/script.vim line 123
            #                            ^--------^
            #
            # And `substitute()` replaces ` line 123` into `:123`.
            #}}}
            trailer: matchstr(v, '/\zs[^/\\]*$')->substitute(' [^ ]* ', ':', ''),
            # Don't invoke `ExpandTilde()` right now; it might be a little costly.{{{
            #
            # It was too costly in the past when we used `expand()`.  Now we use
            # `ExpandTilde()`, which relies on  `substitute()` and is faster, so
            # I don't know whether it would be still too costly.
            #}}}
            location: matchstr(v, 'Last set from .* line \d\+$'),
            }))

    if sourcetype == 'Commands'
        # Remove heading:{{{
        #
        #     Name              Args Address Complete    Definition
        #}}}
        remove(source, 0)
    endif

    # align all the names of commands/mappings in a field (max 35 cells)
    var longest_name: number = mapnew(source,
            (_, v) => v.text->matchstr('^\S*')->strchars(true))
        ->max()
    longest_name = min([35, longest_name])
    source->map((_, v) => extend(v, {
        text: matchstr(v.text, '^\S*')->printf('%-' .. longest_name .. 'S')
            .. ' ' .. matchstr(v.text, '^\S*\s\+\zs.*')
        }))
enddef

def InitHelpTags() #{{{2
    var tagfiles: list<string> = globpath(&rtp, 'doc/tags', true, true)

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
        var awkpgm: list<string> =<< trim END
            {
                match($0, "[^:]*:([^\t]*)\t([^\t]*)\t", a);
                printf("%-40s\t%s\n", a[1], a[2]);
            }
        END
        formatting_cmd = 'awk ' .. join(awkpgm, '')->shellescape()
    endif

    # No need to use `rg(1)`; `grep(1)` is faster here.{{{
    #
    # If you still want to use `rg(1)`, make sure to suppress the display of the
    # line and column numbers:
    #
    #     rg --no-line-number --no-column '.*' ...
    #        ^--------------------------^
    #}}}
    var shellpipeline: string = 'grep -H ".*" '
        .. map(tagfiles, (_, v) => shellescape(v))
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
    #}}}
    Job_start(shellpipeline)
enddef

def InitRecentFiles() #{{{2
    var recentfiles: list<string> = BuflistedSorted()
        + copy(v:oldfiles)->filter((_, v) => ExpandTilde(v)->filereadable())
    map(recentfiles, (_, v) => fnamemodify(v, ':p'))
    var curbuf: string = expand('%:p')
    source = recentfiles
        ->filter((_, v) => v != '' && v != curbuf && !isdirectory(v))
        ->Uniq()
        ->mapnew((_, v) => ({
            text: fnamemodify(v, ':~:.'),
            trailer: '',
            location: ''
            }))
enddef

def InitRegisters() #{{{2
    source = execute('reg')
        ->split('\n')[1 :]
        # trim leading whitespace  (useful to filter based on  type; e.g. typing
        # `^b` will leave only blockwise registers)
        ->map((_, v) => substitute(v, '^\s\+', '', ''))
        ->mapnew((_, v) => matchlist(v, '^\(\S  "\S   \)\(.*\)'))
        ->mapnew((_, v) => ({text: v[2], header: v[1], trailer: '', location: ''}))
enddef

def Job_start(cmd: string) #{{{2
# TODO: *Sometimes*, after pressing `C-c` while a job is running:{{{
#
#    - the job keeps running
#    - the command-line is not cleared
#
# I think that's because we sometimes invoke `UpdatePopups()` with a timer.
# It's possible that  we kill the popup,  and a timer's callback  still tries to
# update it afterward.
#
# But this  begs the question:  how is  it possible for  the popup to  be closed
# without the exit callback being invoked?
#
# Update: I think I can reproduce the issue even without the timer(s).
# Find a MWE:
#
#    - run this command in a separate tmux pane:
#
#         $ watch -n 0.1 pidof find
#
#    - start Vim from your $HOME
#
#    - press `SPC ff`
#}}}
    source_is_being_computed = true
    myjob = job_start(['/bin/sh', '-c', cmd], {
        out_cb: SetIntermediateSource,
        exit_cb: SetFinalSource,
        mode: 'raw',
        noblock: true,
        })
enddef

def SetIntermediateSource(_c: channel, argdata: string) #{{{2
    # We don't have the guarantee that when this async function will be called, we still have a source to process.{{{
    #
    # We  might have  interrupted  the job  one way  or  another (`ESC`,  `C-c`,
    # `BailOutIfTooBig()`, ...).
    #
    # As a  test, enter a  directory with a  lot of files  (e.g. `$HOME`), press
    # `SPC ff`, then `ESC`.  No error should ever be raised; such as this one:
    #
    #     E684: list index out of range: 1
    #}}}
    if sourcetype == ''
        return
    endif
    var data: string
    if incomplete != ''
        data = incomplete .. argdata
    else
        data = argdata
    endif
    var splitted_data: list<string> = split(data, '\n\ze.')
    # The last line of `argdata` does not necessarily match a full shell output line.
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
    if sourcetype == 'Files' || sourcetype == 'Locate' || sourcetype == 'Grep'
        splitted_data
            # TODO: How faster would be our code without this `map()`, on huge sources?{{{
            #
            # Maybe we should get rid of this transformation.
            # If you need to bind a location to a line, include it in the popup buffer.
            # And if you don't want to see it, conceal it.
            # That shouldn't  be too costly  now that we  limit the size  of the
            # popup buffer.
            #}}}
            ->mapnew((_, v) => ({text: v, trailer: '', location: ''}))
            ->AppendSource()
    # TODO: For `Grep`, our filtering text is also matched against the filepath.
    # It should only be matched against real text.
    else
        splitted_data
            ->mapnew((_, v) => split(v, '\t'))
            ->mapnew((_, v) => ({text: v[0], trailer: v[1], location: ''}))
            ->AppendSource()
    endif
    BailOutIfTooBig()
enddef

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
    if sourcetype == ''
        return
    endif
    # the last line of the shell ouput ends with an undesirable trailing newline
    incomplete = incomplete->trim("\<NL>", 2)
    if sourcetype == 'Files' || sourcetype == 'Locate' || sourcetype == 'Grep'
        [{text: incomplete, trailer: '', location: ''}]->AppendSource()
    else
        var parts: list<string> = split(incomplete, '\t')
        [{text: parts[0], trailer: parts[1], location: ''}]->AppendSource()
    endif
    source_is_being_computed = false
    UpdatePopups()
enddef

def AppendSource(l: list<dict<string>>) #{{{2
    source += l
    MaybeUpdatePopups()
enddef

def PopupFilter(id: number, key: string): bool #{{{2
# Handle the keys typed in the popup menu.
# Narrow down the lines based on the keys typed so far.

    # filter the names based on the typed key and keys typed before
    if key =~ '^\p$'
        filter_text ..= key
        if key !~ '\s'
            UpdatePopups()
        endif
        return true

    # clear the filter text entirely
    elseif key == "\<c-u>"
        filter_text = ''
        # The popup menu might get empty without this.
        last_filtered_line = -1
        UpdatePopups()
        return true

    # erase only one character from the filter text
    elseif key == "\<bs>" || key == "\<c-h>"
        if len(filter_text) >= 1
            filter_text = filter_text[: -2]
            UpdatePopups()
        endif
        return true

    # select a neighboring line
    elseif index(["\<down>", "\<up>", "\<c-n>", "\<c-p>"], key) >= 0
        var curline: number = line('.', menu_winid)
        var lastline: number = line('$', menu_winid)
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

        moving_in_popup = true
        timer_stop(moving_in_popup_timer)
        moving_in_popup_timer = timer_start(UPDATEPREVIEW_WAITINGTIME,
            () => execute('moving_in_popup = false'))

        var cmd: string = 'norm! ' .. (key == "\<c-n>" || key == "\<down>" ? 'j' : 'k')
        win_execute(menu_winid, cmd)
        UpdatePopups(false)
        return true

    # select first or last line
    elseif key == "\<c-g>"
        if line('.', menu_winid) == 1
            win_execute(menu_winid, 'norm! G')
        else
            win_execute(menu_winid, 'norm! 1G')
        endif
        UpdatePopups(false)
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

    elseif key == "\<c-o>" && sourcetype =~ '^Registers'
        ToggleSelectedRegisterType()
        return true

    elseif index(["\<c-s>", "\<c-t>", "\<c-v>"], key) >= 0
        popup_close(menu_winid, {
            howtoopen: {
                ["\<c-s>"]: 'insplit',
                ["\<c-t>"]: 'intab',
                ["\<c-v>"]: 'invertsplit'
                }[key],
            idx: line('.', menu_winid),
        })
        return true

    # prevent title from  flickering when `CursorHold` is fired, and  we have at
    # least one autocmd listening
    elseif key == "\<CursorHold>"
        return true
    endif

    return popup_filter_menu(menu_winid, key)
enddef

def MaybeUpdatePopups() #{{{2
# Purpose: Don't update the popups too often while a source is being computed by
# numerous job callbacks.
    var current_source_length: number = len(source)

    # if enough lines have been accumulated
    if current_source_length - last_filtered_line >= SOURCE_CHUNKSIZE
      # or if there are still some lines to process and the source has not changed since last time
      || last_filtered_line < current_source_length - 1
      && last_source_length == current_source_length
        UpdatePopups()
    endif

    last_source_length = current_source_length
enddef

def UpdatePopups(main_text = true) #{{{2
    if main_text
        try
            UpdateMainText()
        catch
            echohl ErrorMsg
            echom v:exception
            echohl NONE
            # We can't close the popup menu from `Clean()`.{{{
            #
            # It would cause the exit callback  to be invoked, which would cause
            # `Clean()` to be invoked, which would cause the exit callback to be
            # invoked... which would raise `E132`:
            #
            #     E132: Function call depth is higher than 'maxfuncdepth'
            #}}}
            popup_close(menu_winid)
            Clean()
            return
        endtry
    endif

    UpdateMainTitle()

    # no need to update the preview while we're moving in the popup with `C-n` and `C-p`
    timer_stop(preview_timer)
    var time: number = moving_in_popup ? UPDATEPREVIEW_WAITINGTIME : 0
    preview_timer = timer_start(time, UpdatePreview)
enddef

def UpdateMainText() #{{{2
# update the popup with the new list of lines
    var filter_text_has_changed: bool = filter_text != last_filter_text
    last_filter_text = filter_text
    if filter_text_has_changed
        filtered_source = []
        last_filtered_line = -1
        popup_settext(menu_winid, '')
    # Bail out if the popup is full, and we haven't type anything yet.{{{
    #
    # The  only reason  to  let the  function  run further,  is  to find  better
    # matches.   If we  haven't  typed  anything, there  is  no better  matches,
    # because we need some filtering text to score them.
    #
    # Besides, it makes the initial contents of the popup nicer.
    # E.g.,  if  we don't  return,  the  initial help  tags  are  not like  what
    # `:FzHelpTags` used to display; i.e. the user manual tags, in order.
    #}}}
    elseif line('$', menu_winid) == POPUP_MAXLINES
        # But don't bail out, even if we *have* typed some filtering text. {{{
        #
        # Splitting the source in chunks fucks up the sorting.
        # If you bail out,  the displayed matches won't be that  good when there are
        # more than what the popup can display.
        # You  can check  this  out by  comparing the  popup's  contents when  using
        # `locate(1)` and the pattern `foobar`, to this Vim expression:
        #
        #     :echo systemlist('locate /')->matchfuzzy('foobar')
        #
        # We need to let our code try to find better matches, even when the popup is
        # full.
        #}}}
        && filter_text !~ '\S'
        return
    endif

    var current_source_length: number = len(source)
    new_last_filtered_line = min([
        last_filtered_line + SOURCE_CHUNKSIZE,
        current_source_length - 1
        ])
    var lines: list<dict<string>> = source[
        last_filtered_line + 1 : new_last_filtered_line
        ]
    var popup_lines: list<dict<any>> = FilterAndHighlight(lines)
    # Don't try to append lines in the popup.{{{
    #
    # We  really want  to reset  the  entire popup  every  time a  new chunk  is
    # processed, because we need to re-sort all the lines.
    #}}}
    popup_settext(menu_winid, popup_lines)
    last_filtered_line = new_last_filtered_line

    # if we haven't filtered all lines, start a timer to finish the work later
    if new_last_filtered_line < current_source_length - 1
      # if the source is still being computed, the popups will be updated automatically,
      # the next time the source is updated
      && !source_is_being_computed
        timer_stop(popups_update_timer)
        popups_update_timer = timer_start(0, () => UpdatePopups())
    endif

    # Rationale:{{{
    #
    # Suppose we're currently selecting the line `34`.
    # We type a new character, which filters out some lines; only `12` remain.
    # We're now automatically selecting line `12`; but the view is wrong; we can
    # only see line `12`, and not the previous ones.  This is jarring.
    # Let's  fix that  by automatically  selecting the  first line  whenever the
    # filter text changes.
    #
    # Besides, that's what `fzf(1)` does.
    #}}}
    if filter_text_has_changed
        win_execute(menu_winid, 'norm! 1G')
    endif

    EchoSourceAndFilterText()
enddef

def FilterAndHighlight(lines: list<dict<string>>): list<dict<any>> #{{{2
    # add info to get highlight via text properties
    if filter_text =~ '\S'
        var matches: list<dict<any>>
        var pos: list<list<number>>
        var scores: list<number>
        [matches, pos, scores] = matchfuzzypos(lines, filter_text, {key: 'text'})
        matches = matches
            ->slice(0, POPUP_MAXLINES)
            # No need to process *all* the matches.
            # The popup can only display a limited amount of them.
            ->mapnew(InjectTextProps(filter_text, pos, scores))
        # `filtered_source` needs  to be  updated now, so  that `ExitCallback()`
        # works as expected later (i.e. can determine which entry we've chosen).
        filtered_source += matches
        filtered_source = filtered_source
            # Don't use `MIN_SCORE` when we've only typed a single character.{{{
            #
            # Otherwise,  we  might  get  more matches  after  adding  a  second
            # character in the filtering text, which is jarring.
            #}}}
            ->filter(strlen(filter_text) <= 1 ? (_, v) => v.score > 0 : (_, v) => v.score > MIN_SCORE)
            ->sort((a, b) => a.score == b.score ? 0 : a.score > b.score ? -1 : 1)
            ->slice(0, POPUP_MAXLINES)

        return filtered_source
    else
        return lines
            ->slice(0, POPUP_MAXLINES)
            ->mapnew(InjectTextProps())
    endif
enddef

def InjectTextProps( #{{{2
    filter_text = '',
    pos: list<list<number>> = [],
    scores: list<number> = []
    ): func(number, dict<any>): dict<any>

    if filter_text !~ '\S' && sourcetype !~ '^Registers'
        return (_, v: dict<string>) => ({
            text: v.text .. "\t" .. v.trailer,
            props: [{
                col: v.text->strlen() + 1,
                end_col: popup_width,
                type: 'fuzzyTrailer'
                }],
            location: v.location,
            })

    elseif filter_text !~ '\S' && sourcetype =~ '^Registers'
        return (_, v: dict<string>) => ({
            header: v.header,
            text: v.header .. v.text .. "\t" .. v.trailer,
            props: [{
                col: 0,
                end_col: v.header->strlen(),
                type: 'fuzzyHeader'
                }]
            + [{
                col: (v.header .. v.text)->strlen() + 1,
                end_col: popup_width,
                type: 'fuzzyTrailer'
                }],
            })

    elseif filter_text =~ '\S' && sourcetype !~ '^Registers'
        return (i: number, v: dict<any>) => ({
            text: v.text .. "\t" .. v.trailer,
            props: mapnew(pos[i], (_, w: number) => ({
                col: w + 1,
                length: 1,
                type: 'fuzzyMatch'
                }))
            + [{
                col: v.text->strlen() + 1,
                end_col: popup_width,
                type: 'fuzzyTrailer'
                }],
            location: v.location,
            score: scores[i]
            })

    elseif filter_text =~ '\S' && sourcetype =~ '^Registers'
        return (i: number, v: dict<any>) => ({
            header: v.header,
            text: v.header .. v.text .. "\t" .. v.trailer,
            props: mapnew(pos[i], (_, w: number) => ({
                col: w + 1 + strlen(v.header),
                length: 1,
                type: 'fuzzyMatch'
                }))
            + [{
                col: 0,
                end_col: v.header->strlen(),
                type: 'fuzzyHeader'
                }]
            + [{
                col: (v.header .. v.text)->strlen() + 1,
                end_col: popup_width,
                type: 'fuzzyTrailer'
                }],
            score: scores[i]
            })
    endif

    return (_, __) => ({})
enddef

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
        var newtitle: string = popup_getoptions(menu_winid)
            ->get('title', '')
            # Why do you replace the total?  It seems useless.{{{
            #
            # It's only useless when the source has been fully computed.
            #
            # Suppose we type  some filtering text which  doesn't match anything
            # while the source is still being  computed.  If we just replace the
            # first 2 numbers:
            #
            #     ->substitute('\d\+/\d\+', '0/0', '')
            #
            # Then, the total won't be updated in the title.
            #}}}
            ->substitute('\d\+/\d\+ ([,0-9]\+)', len(source)->printf('0/0 (%d)'), '')
        popup_setoptions(menu_winid, {title: newtitle})
        popup_setoptions(preview_winid, {title: ''})
        return
    endif

    var curline: number = line('.', menu_winid)
    var lastline: number = line('$', menu_winid)
    var newtitle: string = popup_getoptions(menu_winid)
        ->get('title', '')
        ->substitute('\d\+', curline, '')
        ->substitute('/\zs>\=\d\+', (
                (
                # In theory, this condition is wrong.{{{
                #
                # The filtered source could have reached the limit of the popup,
                # without going beyond; in which case, we should not add the `>`
                # symbol.  But in practice, it's good enough.
                #}}}
                len(filtered_source) == POPUP_MAXLINES
                || filter_text !~ '\S' && len(source) > POPUP_MAXLINES
                ) ? '>' : ''
            ) .. lastline,
            '')
        ->substitute('(\zs[,0-9]\+\ze)', len(source)->string()->FormatBigNumber(), '')
    popup_setoptions(menu_winid, {title: newtitle})
enddef

def UpdatePreview(timerid = 0) #{{{2
    var line: string = getbufline(menu_buf, line('.', menu_winid))->get(0, '')

    # clear the preview if nothing matches the filtering pattern
    if line == ''
        popup_settext(preview_winid, '')
        return
    endif

    var info: dict<string> = line->ExtractInfo()
    if empty(info)
        return
    elseif sourcetype =~ '^Registers'
        popup_setoptions(preview_winid, {title: ' "' .. info.registername .. ' '})
        popup_settext(preview_winid, getreg(info.registername, true, true))
        return
    endif

    var filename: string = info.filename

    # TODO: It would  be convenient for `M-n` to toggle  line numbers in the
    # preview window.
    popup_setoptions(preview_winid, {title: ''})
    if !filereadable(filename)
        filename->PreviewSpecialFile()
        return
    # don't preview a huge file (takes too much time)
    elseif filename->getfsize() > PREVIEW_MAXSIZE
        win_execute(preview_winid, 'syn clear')
        popup_settext(preview_winid, 'cannot preview file bigger than '
            .. float2nr(PREVIEW_MAXSIZE / pow(2, 20)) .. ' MiB')
        return
    endif

    var text: list<string> = readfile(filename)
    popup_settext(preview_winid, text)

    PreviewHighlight(info)
enddef

def ExtractInfo(line: string): dict<string> #{{{3
    if sourcetype == 'Commands' || sourcetype =~ '^Mappings'
        var matchlist: list<string> = (filtered_source ?? source)
            ->get(line('.', menu_winid) - 1, {})
            ->get('location', '')
            ->matchlist('Last set from \(.*\) line \(\d\+\)$')
        if len(matchlist) < 3
            return {}
        endif
        return {
            filename: matchlist[1]->ExpandTilde(),
            lnum: matchlist[2],
            }
    endif

    var splitted: list<string>
    if sourcetype == 'Grep'
        splitted = line
            # remove text; only keep filename and line number
            ->matchstr('^.\{-}:\d\+\ze:')
            ->split('.*\zs:')
    elseif sourcetype =~ '^Registers'
        return {registername: line->matchstr('"\zs.')}
    else
        splitted = line->split('\t\+')
    endif

    if index(['Files', 'Locate', 'RecentFiles'], sourcetype) >= 0
        if splitted->len() != 1
            return {}
        else
            return {
                filename: splitted[0]->ExpandTilde()->fnamemodify(':p'),
                }
        endif
    elseif sourcetype == 'HelpTags'
        return {
            tagname: splitted[0]->trim()->substitute("'", "''", 'g')->escape('\'),
            # Why passing "true, true" as argument to `globpath()`?{{{
            #
            # The  first  `true` can  be  useful  if  for  some reason  `'suffixes'`  or
            # `'wildignore'` are misconfigured.
            # The second  `true` is useful to  handle the case where  `globpath()` finds
            # several files.  It's easier to extract the first one from a list than from
            # a string.
            #}}}
            filename: globpath(&rtp, 'doc/' .. splitted[1], true, true)->get(0, ''),
            }
    else
        return {
            filename: splitted[0]->ExpandTilde()->fnamemodify(':p'),
            lnum: splitted[1],
            }
    endif
enddef

def PreviewSpecialFile(filename: string) #{{{3
    win_execute(preview_winid, 'syn clear')
    var text: string = {
        file: 'File not readable',
        dir: 'Directory',
        link: 'Symbolic link',
        bdev: 'Block device',
        cdev: 'Character device',
        socket: 'Socket',
        fifo: 'FIFO',
        other: 'unknown',
        }->get(getftype(filename), '')
    if text == 'Directory'
        try
            popup_settext(preview_winid, readdir(filename))
        catch /^Vim\%((\a\+)\)\=:E484:/
            popup_settext(preview_winid, 'Cannot read directory')
        endtry
        popup_setoptions(preview_winid, {title: ' Directory'})
    else
        popup_settext(preview_winid, text)
    endif
enddef

def PreviewHighlight(info: dict<string>) #{{{3
    var filename: string
    var lnum: string
    var tagname: string
    if has_key(info, 'filename')
        filename = info.filename
    endif
    if has_key(info, 'lnum')
        lnum = info.lnum
    endif
    if has_key(info, 'tagname')
        tagname = info.tagname
    endif

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
        # `silent!` to suppress a possible error.{{{
        #
        # Such as the ones raised here:
        #
        #     $ vim --clean --cmd 'let mapleader = "\<s-f5>"' /tmp/file.adb
        #     E329: No menu "PopUp"~
        #     E488: Trailing characters: :call ada#List_Tag ()<CR>: al :call ada#List_Tag ()<CR>~
        #     E329: No menu "Tag"~
        #     ...~
        #
        # Those are  weird errors.  But the  point is that no  matter the error,
        # we're not interested in reading its message now.
        #}}}
        var setsyntax: string = 'syn clear | sil! do filetypedetect BufReadPost '
            .. fnameescape(filename)
        var fullconceal: string = '&l:cole = 3'
        var unfold: string = 'norm! zR'
        var whereAmI: string = sourcetype == 'Commands' || sourcetype =~ '^Mappings'
            ? '&l:cul = true'
            : ''
        win_execute(preview_winid, [setsyntax, fullconceal, unfold, whereAmI])
    enddef

    # syntax highlight the text
    if sourcetype == 'HelpTags'
        var setsyntax: list<string> =<< trim END
            if get(b:, 'current_syntax', '') != 'help'
            do Syntax help
            endif
        END
        var searchcmd: string = printf("echo search('\\*\\V%s\\m\\*', 'n')", tagname)
        # Why not just running `search()`?{{{
        #
        # If you just run `search()`, Vim won't redraw the preview popup.
        # You'll need to run `:redraw`; but the latter causes some flicker (with the
        # cursor, and in the statusline, tabline).
        #}}}
        lnum = win_execute(preview_winid, searchcmd)->trim("\<NL>")
        var showtag: string = 'norm! ' .. lnum .. 'G'
        win_execute(preview_winid, setsyntax + ['&l:cole = 3', showtag])

    elseif sourcetype == 'Commands' || sourcetype == 'Grep' || sourcetype =~ '^Mappings'
        win_execute(preview_winid, 'norm! ' .. lnum .. 'Gzz')
        Prettify()
        popup_setoptions(preview_winid, {title: ' ' .. filename})

    elseif index(['Files', 'Locate', 'RecentFiles'], sourcetype) >= 0
        Prettify()
        if sourcetype == 'Locate'
            popup_setoptions(preview_winid, {title: ' ' .. filename->fnamemodify(':t')})
        endif
    endif
enddef
#}}}2
def ExitCallback(type: string, id: number, result: any) #{{{2
    var idx: any = result
    var howtoopen: string = ''
    if typename(result) == 'number' && result <= 0
        # If a job  has been started, and  we want to kill it  by pressing `C-c`
        # because  it takes  too much  time, `job_stop()`  must be  invoked here
        # (which `Clean()` does).
        Clean()
        return
    elseif typename(result) =~ '^dict'
        idx = result.idx
        howtoopen = result.howtoopen
    endif

    try
        if sourcetype =~ '^Registers'
            var regname: string = (filtered_source ?? source)
                ->get(idx - 1)
                ->get('header', '')
                ->matchstr('^[bcl]  "\zs.')
            var prefixkey: string = sourcetype->matchstr('Registers\zs.*')
            if prefixkey == '<c-r>'
                feedkeys((col('.') >= col('$') - 1 ? 'a' : 'i') .. "\<c-r>\<c-r>" .. regname, 'in')
            else
                feedkeys(prefixkey .. regname, 'in')
            endif
            return
        endif

        var chosen: string = (filtered_source ?? source)
            ->get(idx - 1, {})
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
        if index(['Files', 'Locate', 'RecentFiles'], sourcetype) >= 0
            Open(chosen, howtoopen)

        elseif type == 'Grep'
            matchlist(chosen, '^\(.\{-}\):\(\d\+\):')
                ->Open(howtoopen)
        elseif type == 'HelpTags'
            exe 'h ' .. chosen

        elseif type == 'Commands' || type =~ '^Mappings'
            get(filtered_source ?? source, idx - 1, {})
                ->get('location')
                ->matchlist('Last set from \(.*\) line \(\d\+\)$')
                ->Open(howtoopen)
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

def Open(matchlist: any, how: string) #{{{2
    var cmd: string = get({
        insplit: 'sp',
        intab: 'tabe',
        invertsplit: 'vs'
        }, how, 'e')

    var filename: string
    if matchlist->typename() == 'string'
        filename = matchlist
        exe cmd .. ' ' .. filename->fnameescape()
        return
    endif

    if matchlist->typename() == 'list<string>' && len(matchlist) < 3
        return
    endif

    var lnum: string
    [filename, lnum] = matchlist[1 : 2]
    exe cmd .. ' ' .. filename->fnameescape()
    exe 'norm! ' .. lnum .. 'G'
enddef

def Clean() #{{{2
    # the job  makes certain assumptions  (like the existence of  popups); let's
    # stop it  first, to avoid  any issue if we  break one of  these assumptions
    # later
    if job_status(myjob) == 'run'
        job_stop(myjob)
    endif

    timer_stop(popups_update_timer)
    popup_close(preview_winid)

    # clear the message displayed at the command-line
    echo ''
    # since this might break some assumptions in our code, let's keep it at the end
    Reset()
enddef

def Reset() #{{{2
    filter_text = ''
    filtered_source = []
    incomplete = ''
    last_filter_text = ''
    last_filtered_line = -1
    last_source_length = -1
    menu_buf = -1
    menu_winid = -1
    moving_in_popup = false
    moving_in_popup_timer = -1
    new_last_filtered_line = -1
    popups_update_timer = -1
    preview_timer = -1
    preview_winid = -1
    source = []
    source_is_being_computed = false
    sourcetype = ''
enddef
#}}}1
# Utility {{{1
def Error(msg: string) #{{{2
    echohl ErrorMsg
    echom msg
    echohl None
enddef

def BailOutIfTooBig() #{{{2
    if len(source) <= TOO_BIG
        return
    endif
    popup_close(menu_winid)
    Clean()
    # the timer avoids a hit-enter prompt
    timer_start(0, () =>
        printf('Cannot process more than %d entries', TOO_BIG)
            ->Error())
enddef

def EchoSourceAndFilterText() #{{{2
    echohl ModeMsg
    echo sourcetype->substitute('\l\zs\ze\u', ' ', 'g') .. ': '
    echohl Title
    echon filter_text
    echohl NONE
enddef

def UtilityIsMissing(): bool #{{{2
    if sourcetype == 'HelpTags'
        if !(executable('rg') || executable('grep')) || !(executable('perl') || executable('awk'))
            Error('Require rg/grep and perl/awk')
            return true
        endif
    elseif sourcetype == 'Files'
        # TODO: Use `fd(1)` (because faster).  If not available, fall back on `find(1)`.{{{
        #
        # I think  `fd(1)`'s equivalent  of `-ipath`  is `--full-path`,  and the
        # equivalent of `-prune` is `--prune`.
        #}}}
        if !executable('find')
            Error('Require find')
            return true
        endif
    elseif sourcetype == 'Grep'
        if !executable('rg') && !executable('grep')
            Error('Require rg/grep')
            return true
        endif
    endif
    return false
enddef

def BuflistedSorted(): list<string> #{{{2
    # Note: You could also use `undotree()` instead of `lastused`.{{{
    #
    # The maximal precision of `lastused` is only 1s.
    # `undotree()` has a much better precision, but the semantics of the sorting
    # would change; i.e. the sorting would no longer be based on the last time a buffer
    # was active, but on the last time it was changed.
    #}}}
    return getbufinfo({buflisted: true})
        ->filter((_, v) => getbufvar(v.bufnr, '&buftype', '') == '')
        ->map((_, v) => ({bufnr: v.bufnr, lastused: v.lastused}))
        # the most recently active buffers first;
        # for 2 buffers accessed in the same second, the one with the bigger number first
        # (because it's the most recently created one)
        ->sort((a, b) => a.lastused < b.lastused ? 1 : a.lastused == b.lastused ? b.bufnr - a.bufnr : -1)
        ->mapnew((_, v) => bufname(v.bufnr))
enddef

def Uniq(list: list<string>): list<string> #{{{2
    var visited: dict<number>
    var ret: list<string>
    for path in list
        if !empty(path) && !has_key(visited, path)
            add(ret, path)
            visited[path] = 1
        endif
    endfor
    return ret
enddef

def GetFindCmd(): string #{{{2
    # split before any comma which is not preceded by an odd number of backslashes
    var tokens: list<string> = split(&wig, '\%(\\\@<!\\\%(\\\\\)*\\\@!\)\@<!,')

    # ignore files whose name is present in `'wildignore'` (e.g. `tags`)
    var by_name: string = tokens
        ->copy()
        ->filter((_, v) => v !~ '[/*]')
        ->map((_, v) => '-iname ' .. shellescape(v) .. ' -o')
        ->join()

    # ignore files whose extension is present in `'wildignore'` (e.g. `*.mp3`)
    var by_extension: string = tokens
        ->copy()
        ->filter((_, v) => v =~ '\*' && v !~ '/')
        ->map((_, v) => '-iname ' .. shellescape(v) .. ' -o')
        ->join()

    # ignore files whose directory is present in `'wildignore'` (e.g. `*/build/*`)
    # How does `-prune` work?{{{
    #
    # When the  path of a file  matches the glob preceding  `-prune`, the latter
    # returns true; as  a result, the rhs  is not evaluated.  But  when the path
    # does not match,  `-prune` returns false, and the rhs  *is* evaluated.  See
    # `man find /^EXAMPLES/;/construct`.
    #}}}
    var cwd: string = getcwd()
    var by_directory: string = tokens
        ->copy()
        ->filter((_, v) => v =~ '/')
        ->map((_, v) => '-ipath '
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
            .. ' -prune -o')
        ->join()

    var hidden_files: string = '-path ''*/.*'' -prune'
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

def FormatBigNumber(str: string): string #{{{2
    # Problem: It's hard to quickly measure how big a number such as `123456789` is.
    # Solution: Add commas to improve readability.{{{
    #
    #     123456789
    #     →
    #     123,456,789
    #}}}
    # Alternative Implementation:{{{
    #
    #     def FormatBigNumber(str: string): string
    #         return split(str, '\zs')
    #             ->reverse()
    #             ->reduce((a, v) => substitute(a, ',', '', 'g')->len() % 3 == 2 ? ',' .. v .. a : v .. a)
    #             ->trim(',', 0)
    #     enddef
    #
    # Note: It's much slower.
    #}}}
    if len(str) <= 3
        return str
    elseif len(str) % 3 == 1
        return str[0] .. ',' .. FormatBigNumber(str[1 :])
    else
        return str[0] .. FormatBigNumber(str[1 :])
    endif
enddef

def ToggleSelectedRegisterType() #{{{2
# toggle type of selected register (characterwise → linewise → blockwise → ...)

    var lnum: number = line('.', menu_winid)
    var line: string = getbufline(menu_buf, lnum)->get(0, '')
    var matchlist: list<string> = line->matchlist('^\([bcl]\)  "\(.\)')
    if matchlist->len() < 3
        return
    endif
    var regtype: string = matchlist[1]
    var regname: string = matchlist[2]
    setreg(regname, {
        regtype: {b: 'c', c: 'l', l: 'b'}[regtype],
        regcontents: getreg(regname, true, true),
        })

    # reset the source so that the new type is picked up
    InitRegisters()
    # Necessary  to prevent  duplicated entries  from being  added in  the popup
    # menu, each time we press `C-o` while there is a filtering text.
    filtered_source = []
    # Necessary to prevent the popup menu from being emptied.
    last_filtered_line = -1
    # finally, we can refresh the popup menu
    UpdateMainText()
enddef

