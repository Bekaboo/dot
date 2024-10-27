function __fish_venv_prompt
    if test -n "$VIRTUAL_ENV"
        echo basename $VIRTUAL_ENV
    end
end

function fish_right_prompt --description 'Write out the right prompt'
    set -l vcs_info (string match -gr '([^() ]+)' (fish_vcs_prompt))
    set -l venv_info (test -n "$VIRTUAL_ENV"
        and echo (basename $VIRTUAL_ENV)
        or echo '')

    set -l info (string join ', ' (string match -v '' $venv_info $vcs_info))
    if test -n "$info"
        echo -n -s (set_color $fish_color_vcs) '(' $info ')'
    end
end
