complete -c macos-im-switch -f

complete -c macos-im-switch -n __fish_use_subcommand -a list -d 'List available input sources'
complete -c macos-im-switch -n __fish_use_subcommand -a current -d 'Show current input source'
complete -c macos-im-switch -n __fish_use_subcommand -a set -d 'Set input source'

complete -c macos-im-switch -n '__fish_seen_subcommand_from set' -a '(macos-im-switch list 2>/dev/null | awk \'{print $NF}\')' -d 'Input source ID'
