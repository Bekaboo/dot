function __python_venv \
    --on-variable PWD \
    --description 'Automatically activate or deactivate python virtualenvs'
    if not type -q python3
        return
    end

    set -l activation_file ''
    # $VIRTUAL_ENV not set -- python virtualenv not activated, try to
    # activate it if '.env/bin/activate.fish' or '.venv/bin/activate.fish'
    # exists
    if test -z "$VIRTUAL_ENV"
        set -l path "$PWD"
        while test $path != (dirname $path)
            if test -e "$path/.env/bin/activate.fish"
                chmod +x "$path/.env/bin/activate.fish"
                source "$path/.env/bin/activate.fish"
                return
            else if test -e "$path/.venv/bin/activate.fish"
                chmod +x "$path/.venv/bin/activate.fish"
                source "$path/.venv/bin/activate.fish"
                return
            end
            set path (dirname $path)
        end
        return
    end

    # $VIRTUAL_ENV set but 'deactivate' not found -- python virtualenv
    # activated in parent shell, try to activate in current shell if currently
    # in project directory or a subdirectory of the project directory
    set -l parent_dir (dirname "$VIRTUAL_ENV")
    if not type -q deactivate
        if issubdir "$PWD" "$parent_dir"
            set activation_file (type -sp activate.fish)
            chmod +x "$activation_file"
            source "$activation_file"
            return
        end
    end

    # $VIRTUAL_ENV set and 'deactivate' found -- python virtualenv activated
    # in current shell, try to deactivate it if currently not inside the
    # project directory or a subdirectory of the project directory
    if not issubdir "$PWD" "$parent_dir"; and type -q deactivate
        deactivate
    end
end

__python_venv
