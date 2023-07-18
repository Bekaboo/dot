function fish_prompt --description 'Write out the prompt'
    set -l last_status $status

    # Color the prompt differently when we're root
    set -l color_cwd $fish_color_cwd
    if functions -q fish_is_root_user; and fish_is_root_user
        set color_cwd $fish_color_cwd_root
    end

    # Use normal color if the last command exit with 0
    test $last_status -eq 0
        and set -l color_status $fish_color_status_0
        or  set -l color_status $fish_color_status

    echo -n -s \n '  ' \
        (set_color $color_status) ' ' $last_status ' ' \
        (set_color normal) (set_color $color_cwd) ' ' (prompt_pwd) \
        (set_color normal) (set_color $fish_color_vcs) \
            (string replace -r '^(\s*\()(\w+)' '$1\#$2' \
                (fish_vcs_prompt)) ' ' \
        (set_color normal) ' '
end
