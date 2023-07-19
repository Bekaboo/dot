function rm \
        --wraps 'rm' \
        --description 'Alias for trash'
    if not type -q trash
        read -l -P 'trash not found, remove anyway? [y/N] ' response
        switch $response
            case y Y
                return (command rm $argv)
            case *
                return 1
        end
    end
    trash $argv
end
