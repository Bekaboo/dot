# Disable file completions by default
complete -c bak -f

# Main options
complete -c bak -s h -l help -d "Show help message"
complete -c bak -s m -l move -d "Use move instead of copy"
complete -c bak -s R -l restore -d "Restore from backup"

# Condition-sensitive argument completion
complete -c bak -n "__fish_contains_opt -s R restore" -a "(__fish_suffix .bak)"
complete -c bak -n "not __fish_contains_opt -s R restore" -a "(__fish_complete_path)"
