function __fish_venv_prompt
    if test -n "$VIRTUAL_ENV"
        echo (basename $VIRTUAL_ENV)
        return
    end

    if type -q pyenv
        set -l venv (pyenv version-name 2>/dev/null)
        if test "$venv" = system
            return
        end
        echo $venv
    end
end
