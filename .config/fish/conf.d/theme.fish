if not status is-interactive
    exit
end

function __fish_reload_theme \
    --on-variable __fish_reload_theme \
    --description 'Switch fish theme'
    for theme in 'Current' 'Default Dark'
        if test -f "$__fish_config_dir/themes/$theme.theme"
            fish_config theme choose $theme 2>/dev/null
            break
        end
    end
    commandline -f repaint
end

__fish_reload_theme
