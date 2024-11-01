function fish_greeting
    if not status is-login
        return
    end
    if type -q neofetch
        clear -x
        neofetch
    end
end
