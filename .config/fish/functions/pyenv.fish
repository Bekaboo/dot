# Pyenv config, see:
# https://github.com/pyenv/pyenv?tab=readme-ov-file#b-set-up-your-shell-environment-for-pyenv

function pyenv
    # Add `pyenv` executable to path if not yet initialized
    if test -z "$PYENV_ROOT"; and test -d "$HOME/.pyenv"
        set -Ux PYENV_ROOT $HOME/.pyenv
    end
    if test -n "$PYENV_ROOT"
        fish_add_path $PYENV_ROOT/bin
    end

    # Temporarily remove our wrapper function to prevent infinite recursion
    # during init when completions are loaded
    #
    # This is only needed on macOS -- on Linux there's no recursion issue
    # without this (why?)
    functions -e pyenv

    # Should redefine `pyenv` function and use redefined `pyenv` function to
    # execute actual command
    command pyenv init - fish | source; or return
    pyenv $argv
end
