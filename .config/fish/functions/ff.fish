function ff --description 'Use fzf to open files or cd to directories'
    if not type -q fzf; or not type -q fd
        echo 'fzf or fd is not installed' 1>&2
        return 1
    end

    set -l tmpfile "$(mktemp)"
    fd -p -H -L -td -tf -tl --mount -c=always --search-path=$argv[1] \
        | fzf --ansi --query=$argv[2] >$tmpfile

    set -l targets (cat $tmpfile | string split "\n")
    command rm -f $tmpfile
    test (count $targets) = 0; and return 0

    # If there is only one target and it is a directory, cd to it
    if test (count $targets) = 1; and test -d $targets[1]
        cd $targets
        return $status
    end

    # Copy text files and directories to a separate array and
    # use $EDITOR to open them; open other files with xdg-open
    for target in $targets
        if test -d $target
            or string match -req 'text|empty' "$(file -b $target)"
            set -af text_or_dirs $target
        else
            set -af others $target
        end
    end

    if type -q xdg-open
        for other in $others
            xdg-open $other 2>/dev/null
        end
    else if set -q others
        echo 'xdg-open not found, omit opening files: ' $others 1>&2
    end
    if set -q text_or_dirs
        type -q $EDITOR
        and $EDITOR $text_or_dirs
        or echo '$EDITOR not found, omit opening files: ' $text_or_dirs 1>&2
    end
end
