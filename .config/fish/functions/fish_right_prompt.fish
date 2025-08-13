function __fish_async_vcs_prompt
    # Get cached version control info at `$__fish_vcs_info_<cwd>`
    set -l safe_pwd (string replace -ra '[^a-zA-Z0-9_]' '_' -- $PWD)
    set -l vcs_info_name __fish_vcs_info_$safe_pwd

    # Launch async process to update vcs info
    # Don't update if this is invoked by a repaint to avoid endless recursion
    if not set -q __fish_async_prompt_update
        fish -c "
            set -U $vcs_info_name (fish_vcs_prompt)
            kill -USR1 $fish_pid
        " & disown 2>/dev/null
    end

    echo $$vcs_info_name
end

function __fish_async_venv_prompt
    set -l safe_pwd (string replace -ra '[^a-zA-Z0-9_]' '_' -- $PWD)
    set -l venv_info_name __fish_venv_info_$safe_pwd

    if not set -q __fish_async_prompt_update
        fish -c "
            set -U $venv_info_name (__fish_venv_prompt)
            kill -USR1 $fish_pid
        " & disown 2>/dev/null
    end

    echo $$venv_info_name
end

function __fish_async_prompt_repaint --on-signal USR1
    # Set flag `__fish_async_prompt_update` to indicate that the prompt is
    # repainted to update vcs info
    set -g __fish_async_prompt_update true
    # Async call, prompt not updated yet when request exists
    commandline -f repaint
end

function __fish_async_prompt_unset_update \
    --description 'Unset flag on async prompt repaint to re-enable vcs/venv info update' \
    --on-event fish_prompt
    set -e __fish_async_prompt_update
end

function fish_right_prompt --description 'Write out the right prompt'
    set -l vcs_info (string match -r '[^() ]+' (__fish_async_vcs_prompt))
    set -l venv_info (__fish_async_venv_prompt)

    set -l info (string join ', ' (string match -v '' $venv_info $vcs_info))
    if test -z "$info"
        return
    end

    echo -n -s (set_color $fish_color_vcs) '(' $info ')'
end
