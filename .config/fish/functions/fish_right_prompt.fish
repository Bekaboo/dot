function fish_right_prompt --description 'Write out the right prompt'
    echo -n -s \
        (set_color $fish_color_vcs) \
            (string replace -r '^(\s*\()(\w+)' '$1\#$2' \
                (fish_vcs_prompt))
end
