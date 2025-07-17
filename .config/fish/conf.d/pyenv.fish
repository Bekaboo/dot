# Auto init pyenv when detected `.python-version`
function __pyenv \
    --on-variable PWD \
    --description 'Automatically init pyenv'
    if not type -q pyenv
        return
    end

    # Pyenv will exit early and abort detecting python version file if an
    # existing virtual env is detected, so exit current python virtual env if
    # current working directory is outside of virtual env path
    if test -n "$VIRTUAL_ENV"; and not issubdir $VIRTUAL_ENV $PWD
        if type -q deactivate
            deactivate
        end
        set -e VIRTUAL_ENV
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
