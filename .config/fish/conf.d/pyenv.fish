# Auto init pyenv when detected `.python-version`
function __pyenv \
    --on-variable PWD \
    --description 'Automatically init pyenv'
    if not type -q pyenv
        return
    end

    # Getting version from environment variable or the global version config
    # file
    if test -n "$PYENV_VERSION"
        or test -f "$PYENV_ROOT/version"
        or test -f "$HOME/.pyenv/version"
        pyenv init - fish | source
        return
    end

    # Local version file
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
