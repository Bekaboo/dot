# Pyenv config, see:
# https://github.com/pyenv/pyenv?tab=readme-ov-file#b-set-up-your-shell-environment-for-pyenv

function pyenv
    # Initialize shell if not yet Initialized
    if test -z "$PYENV_ROOT"; and test -d "$HOME/.pyenv"
        set -Ux PYENV_ROOT $HOME/.pyenv
        fish_add_path $PYENV_ROOT/bin
        command pyenv init - fish | source; or return
    end

    # Default `pyenv` function
    set command $argv[1]
    set -e argv[1]

    switch "$command"
        case activate deactivate rehash shell
            source (pyenv sh-$command $argv|psub)
        case '*'
            command pyenv $command $argv
    end
end
