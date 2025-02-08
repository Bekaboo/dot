if not status is-interactive
    exit
end

function __fish_reload_theme --on-variable __fish_reload_theme \
    --description 'Switch fish theme'
    if type -q tput; and test (tput colors 2>/dev/null) -lt 256
        fish_config theme choose 'Default Dark' 2>/dev/null
        return
    end
    fish_config theme choose Current 2>/dev/null
    commandline -f repaint
end

__fish_reload_theme
