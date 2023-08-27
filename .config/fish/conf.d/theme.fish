function __term_supports_256color \
        --description 'Check if terminal supports 256 color'
    if test "$COLORTERM" = 'truecolor'
        return 0
    end
    set -l colored_terms 256color wezterm alacritty kitty konsole yakuake
    for term in $colored_terms
        if string match -q --entire $term $TERM
            return 0
        end
    end
    return 1
end

function __fish_reload_theme \
        --on-variable __fish_reload_theme \
        --description 'Switch fish theme'
    __term_supports_256color;
        and test -f "$__fish_config_dir/themes/Current.theme"
        and fish_config theme choose Current
        or  fish_config theme choose 'Base Dark'
    commandline -f repaint
end

__fish_reload_theme
