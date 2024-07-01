function __rsync_watch_complete_ssh_servers \
    --description 'Complete <server> part in ssh addresses with format <username>@<server>:<path>'
    set -l input $argv[1]
    set -l servers (cat ~/.ssh/known_hosts | awk '{print $1}' | cut -d '@' -f 1 | sort -u)
    set -l server_part (string replace -r '^([^@]*)@([^:]*)' '$2' $input)
    set -l compl_prefix (string replace -r "$server_part\$" '' $input)
    for server in $servers
        echo "$compl_prefix$server:"
    end
end

function __rsync_watch_complete_ssh_paths \
    --description 'Complete <path> part in ssh addresses with format <username>@<server>:<path>'
    set -l input $argv[1]
    set -l input_list (string split ":" $input)
    if test (count $input_list) -ne 2
        return
    end

    set -l user_server $input_list[1]
    set -l path_part $input_list[2]
    set -l path_glob (string match -arq '^[^/]' -- $path_part
        and echo "*$path_part*"
        or echo "$path_part*")
    set -l compl_prefix (string replace -r "$path_part\$" '' $input)
    set -l paths (command ssh $user_server "ls -dp $path_glob" 2>/dev/null)
    for path in $paths
        echo "$compl_prefix$path"
    end
end

function __rsync_watch_complete_ssh \
    --description 'Complete ssh addresses in the format of <username>@<server>:<path>'
    set -l input (commandline -ct)

    # Try complete with ssh addresses, if it matches the format;
    # otherwise, complete with local paths
    if string match -q "*@*" -- $input
        string match -q "*@*:*" -- $input
        and __rsync_watch_complete_ssh_paths $input
        or __rsync_watch_complete_ssh_servers $input
    else
        __fish_complete_path $input
    end
end

complete -c rsync-watch -fa '(__rsync_watch_complete_ssh)'
