function fish_greeting
    if not status is-login
        return
    end

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
