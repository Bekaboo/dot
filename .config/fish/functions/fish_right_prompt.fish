function __fish_venv_prompt
    if test -n "$VIRTUAL_ENV"
        echo basename $VIRTUAL_ENV
    end
end

function __fish_async_vcs_prompt
    # Get cached version control info at `$__fish_vcs_info_<cwd>`
    set -l safe_pwd (string replace -ra '[^a-zA-Z0-9_]' '_' -- $PWD)
    set -l vcs_info_name __fish_vcs_info_$safe_pwd

    # Launch async process to update vcs info
    fish -c "set -U $vcs_info_name (fish_vcs_prompt)" & disown 2>/dev/null
    echo $$vcs_info_name
end

function fish_right_prompt --description 'Write out the right prompt'
    set -l vcs_info (string match -r '[^() ]+' (__fish_async_vcs_prompt))
    set -l venv_info (__fish_venv_prompt)

    set -l info (string join ', ' (string match -v '' $venv_info $vcs_info))
    if test -z "$info"
        return
    end

    echo -n -s (set_color $fish_color_vcs) '(' $info ')'
end
