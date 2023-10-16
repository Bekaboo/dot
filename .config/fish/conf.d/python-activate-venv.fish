function python-activate-venv \
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
        if test -e "./.env/bin/activate.fish"
            set activation_file "./.env/bin/activate.fish"
        else if test -e "./.venv/bin/activate.fish"
            set activation_file "./.venv/bin/activate.fish"
        end
        if test -n "$activation_file"
            chmod +x "$activation_file"
            source "$activation_file"
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
    if not issubdir "$PWD" "$parent_dir"
        deactivate
    end
end

python-activate-venv
