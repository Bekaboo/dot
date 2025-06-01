if not status is-interactive
    exit
end

# Auto init pyenv when detected `.python-version`
function __pyenv \
    --on-variable PWD \
    --description 'Automatically init pyenv'
    if not type -q pyenv;
        or test -n "$PYENV_SHELL" # already initialized
        return
    end

    set -l path $PWD
    while test $path != (dirname $path)
        if test -f "$path/.python-version"
            pyenv init - fish | source
            return
        end
        set path (dirname $path)
    end
end

__pyenv
