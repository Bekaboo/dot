function fish_greeting
    if not status is-login
        return
    end
    if type -q neofetch; and type -q script
        clear -x
        # Run in pseudo-terminal to prevent terminal state issues
        # (tmux error: 'not a terminal', etc)
        script -q /dev/null -c neofetch
    end
end
