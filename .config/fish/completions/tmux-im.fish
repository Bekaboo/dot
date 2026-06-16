complete -c tmux-im -f

complete -c tmux-im -n __fish_use_subcommand -a save -d 'Save IM state for a pane'
complete -c tmux-im -n __fish_use_subcommand -a on -d 'Restore IM for a pane'
complete -c tmux-im -n __fish_use_subcommand -a force-off -d 'Force IM off'

complete -c tmux-im -n '__fish_seen_subcommand_from save on' -a '(tmux list-panes -a -F "#{pane_id}" 2>/dev/null)' -d 'Pane ID'
