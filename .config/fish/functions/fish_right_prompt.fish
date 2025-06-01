function __fish_venv_prompt
    if test -n "$VIRTUAL_ENV"
        echo basename $VIRTUAL_ENV
    end
end

function __fish_async_prompt_get_vcs_info_name -a path
    set -l safe_path (string replace -ra '[^a-zA-Z0-9_]' '_' -- $path)
    echo __fish_vcs_info_$safe_path
end

function __fish_async_vcs_prompt
    # Get cached version control info at `$__fish_vcs_info_<cwd>`
    set -l path $PWD
    set -l vcs_info_name (__fish_async_prompt_get_vcs_info_name $path)

    # Launch async process to update vcs info
    # Don't update if this is invoked by a repaint to avoid endless recursive
    # calls
    if not set -q __fish_async_prompt_vcs_update
        fish -c "
            set -U $vcs_info_name (fish_vcs_prompt)
            kill -USR1 $fish_pid
        " & disown 2>/dev/null
    else
    end

    # Find cache with matching path prefix, e.g. for vcs info at `/foo/bar/baz`
    # try cache for `/foo/bar/baz`, `/foo/bar`, `/foo` in order until the first
    # found
    while test (dirname $path) != $path
        if set -q $vcs_info_name
            echo $$vcs_info_name
            return
        end
        set path (dirname $path)
        set vcs_info_name (__fish_async_prompt_get_vcs_info_name $path)
    end
end

function __fish_async_prompt_repaint --on-signal USR1
    # Set flag `__fish_async_prompt_vcs_update` to indicate that the prompt is
    # repainted to update vcs info
    set -g __fish_async_prompt_vcs_update true
    # Async call, prompt not updated yet when request exists, so use a function
    # to unset the update flag on prompt repaint
    commandline -f repaint
    function __fish_async_prompt_undset_update --on-event fish_prompt
        set -e __fish_async_prompt_vcs_update
        functions -e __fish_async_prompt_undset_flag # ensure execute once
    end
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
