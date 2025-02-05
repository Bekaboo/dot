if not status is-interactive
    exit
end

function __fish_reload_theme \
    --on-variable __fish_reload_theme \
    --description 'Switch fish theme'
    test (tput colors 2>/dev/null) -ge 256
    and test -f "$__fish_config_dir/themes/Current.theme"
    and fish_config theme choose Current 2>/dev/null
    or fish_config theme choose 'Default Dark' 2>/dev/null
    commandline -f repaint
end

__fish_reload_theme
