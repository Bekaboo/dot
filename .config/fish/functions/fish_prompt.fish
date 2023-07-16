function fish_prompt --description 'Write out the prompt'
    set -l last_pipestatus $pipestatus

    # Color the prompt differently when we're root
    set -l color_cwd $fish_color_cwd
    if functions -q fish_is_root_user; and fish_is_root_user
        set color_cwd $fish_color_cwd_root
    end

    # Use normal color if the last command exit with 0
    set -l color_status $fish_color_status
    if test $last_pipestatus -eq 0
        set color_status $fish_color_status_0
    end

    echo -n -s \n '  ' \
        (set_color $color_status) ' ' $last_pipestatus ' ' \
        (set_color normal) (set_color $fish_color_pwd) ' ' (prompt_pwd) \
        (set_color normal) (set_color $fish_color_vcs) \
            (string replace -r '^(\s*\()(\w+)' '$1\#$2' \
                (fish_vcs_prompt)) ' ' \
        (set_color normal) ' '
end
