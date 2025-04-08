function __ff_open_files_or_dir --description 'Use xdg to open files'
    # $argv: files to open
    if test (count $argv) = 1; and test -d $argv[1]
        cd $argv
        return $status
    end

    # Copy text files and directories to a separate array and
    # use $EDITOR to open them; open other files with xdg-open
    for target in $argv
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

function ff --description 'Use fzf to open files or cd to directories'
    # $argv[1]: path to start searching from
    # $argv[2]: optional initial query
    set -l path (test -n "$argv[1]"; and echo $argv[1]; or echo $PWD)
    set -l query $argv[2]

    # If there is only one target and it is a file, open it directly
    if test (count $argv) = 1; and test -f "$path"
        __ff_open_files_or_dir $argv
        return
    end

    if not type -q fzf
        echo 'fzf is not executable' 1>&2
        return 1
    end

    set -l tmpfile (mktemp)

    # On some systems, e.g. Ubuntu, fd executable is installed as 'fdfind'
    set -l fd_cmd (type -q fd && echo fd || echo fdfind)
    if type -q $fd_cmd
        $fd_cmd -0 -p -H -L -td -tf -tl -c=always --search-path=$path \
            | fzf --read0 --ansi --query=$query >$tmpfile
    else if type -q find
        find $path -print0 -type d -o -type f -o -type l -follow \
            | fzf --read0 --ansi --query=$query >$tmpfile
    else
        rm -f $tmpfile
        echo 'fd/find is not executable' 1>&2
        return 1
    end

    set -l targets (cat $tmpfile | string split "\n")
    command rm -f $tmpfile
    test (count $targets) = 0; and return 0

    __ff_open_files_or_dir $targets
    return
end
