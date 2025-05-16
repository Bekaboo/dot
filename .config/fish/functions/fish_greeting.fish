function fish_greeting
    if not status is-login
        return
    end
    if type -q neofetch; and type -q script
        clear -x
        # Run in pseudo-terminal to prevent terminal state issues
        # (tmux error: 'not a terminal', etc)
        # macOS `script` does not accept `-c` flag
        if script -c exit &>/dev/null
            script -q /dev/null -c neofetch
        else
            script -q /dev/null neofetch
        end
    end
end
