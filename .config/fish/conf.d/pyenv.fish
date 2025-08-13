function __pyenv_init_once --description 'Helper function to initialize pyenv once'
    # Sometimes pyenv will fail with:
    # 'pyenv: cannot rehash: <HOME>/.pyenv/shims/.pyenv-shim exists'
    # to **stdout** (not stderr) instead of printing correct init script to
    # stdout.
    #
    # Sourcing the error message will surely fail with:
    # fish: Unknown command: pyenv:
    # - (line 1):
    # pyenv: cannot rehash: <HOME>/.pyenv/shims/.pyenv-shim exists
    # ^~~~~^
    # from sourcing file -
    #         called on line 38 of file ~/.config/fish/conf.d/pyenv.fish
    # in function '__pyenv'
    #         called on line 45 of file ~/.config/fish/conf.d/pyenv.fish
    # from sourcing file ~/.config/fish/conf.d/pyenv.fish
    # ...
    #
    # So we have to check the existence of `.pyenv-shim` and return early
    # without sourcing the output if it already exists.
    if not type -q pyenv; or test -e "$HOME/.pyenv/shims/.pyenv-shim"
        return
    end

    # Erase `__pyenv` and `__pyenv_init_once` becausetkkyenv itself will
    # automatically detect and activate global/local python version settings
    # after initialization
    if pyenv init - fish | source &>/dev/null
        functions -e __pyenv __pyenv_init_once
    end
end

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
        __pyenv_init_once
        return
    end

    # Local version file
    set -l path $PWD
    while test $path != (dirname $path)
        if test -f "$path/.python-version"
            __pyenv_init_once
            return
        end
        set path (dirname $path)
    end
end

__pyenv
