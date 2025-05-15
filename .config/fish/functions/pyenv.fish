# Pyenv config, see:
# https://github.com/pyenv/pyenv?tab=readme-ov-file#b-set-up-your-shell-environment-for-pyenv

function pyenv --wraps pyenv --description 'Lazy init pyenv'
    set -l pyenv (which pyenv)
    if test -z "$pyenv"
        command pyenv; or return $status # should have 'unkown command' error
    end

    # Not yet initialized
    if test -z "$PYENV_SHELL"
        set -gx PYENV_ROOT $HOME/.pyenv
        fish_add_path -p $PYENV_ROOT/bin
        $pyenv init - fish | source; or return $status
    end

    $pyenv $argv
end
