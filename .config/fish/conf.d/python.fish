function __python_venv \
    --on-variable PWD \
    --description 'Automatically activate or deactivate python virtualenvs'
    if not type -q python3
        return
    end

    # $VIRTUAL_ENV not set -- python virtualenv not activated, try to
    # activate it if '.env/bin/activate.fish' or '.venv/bin/activate.fish'
    # exists
    if test -z "$VIRTUAL_ENV"
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
        return
    end

    # $VIRTUAL_ENV set but 'deactivate' not found -- python virtualenv
    # activated in parent shell, try to activate in current shell if currently
    # in project directory or a subdirectory of the project directory
    set -l proj_dir (dirname $VIRTUAL_ENV)
    if not type -q deactivate
        if issubdir "$PWD" "$proj_dir"
            set -l activation_file (echo $VIRTUAL_ENV/bin/activate.fish)
            if test -f "$activation_file"
                source "$activation_file"
            end
            return
        end
    end

    # $VIRTUAL_ENV set and 'deactivate' found -- python virtualenv activated
    # in current shell, try to deactivate it if currently not inside the
    # project directory or a subdirectory of the project directory
    if not issubdir $PWD $proj_dir; and type -q deactivate
        deactivate
    end
end

__python_venv
