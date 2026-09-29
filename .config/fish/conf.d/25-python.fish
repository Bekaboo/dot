function __python_venv \
    --on-variable PWD \
    --on-event fish_postexec \
    --description 'Automatically activate or deactivate python virtualenvs'
    if not type -q python3
        return
    end

    set -l path "$PWD"
    while test $path != (dirname $path)
        for venv_dir in venv env .venv .env
            set -l activation_file $path/$venv_dir/bin/activate.fish
            if test -f $activation_file
                source $activation_file
                return
            end
        end
        set path (dirname $path)
    end

    if test -n "$VIRTUAL_ENV"; and type -q deactivate
        deactivate
    end
end

__python_venv
