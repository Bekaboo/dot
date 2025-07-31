# Auto init pyenv when detected `.python-version`
function __pyenv \
    --on-variable PWD \
    --description 'Automatically init pyenv'
    # Early return if `pyenv` is not available or is already initialized
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
        # Erase self because pyenv will automatically detect and activate
        # global/local python version settings after initialization
        pyenv init - fish | source; and functions -e __pyenv
        return
    end

    # Local version file
    set -l path $PWD
    while test $path != (dirname $path)
        if test -f "$path/.python-version"
            pyenv init - fish | source; and functions -e __pyenv
            return
        end
        set path (dirname $path)
    end
end

__pyenv
