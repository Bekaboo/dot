function fish_greeting
    if not status is-login
        return
    end

    test -z $tmp_dir; and set -l tmp_dir $XDG_RUNTIME_DIR
    test -z $tmp_dir; and set -l tmp_dir $TMPDIR
    test -z $tmp_dir; and set -l tmp_dir tmp

    if test -e "$tmp_dir/greeted"
        return
    end
    touch "$tmp_dir/greeted"

    if type -q fastfetch
        set -f fetch fastfetch
    else if type -q neofetch
        set -f fetch neofetch
    end
    if test -z "$fetch"
        return
    end

    # Run in pseudo-terminal to prevent terminal state issues
    # (tmux error: 'not a terminal', etc)
    # macOS `script` does not accept `-c` flag
    if script -q /dev/null -c exit &>/dev/null
        script -q /dev/null -c $fetch
    else
        script -q /dev/null $fetch
    end
end
