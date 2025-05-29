function __complete_ssh_servers \
    --description 'Complete <server> part in ssh addresses with format <username>@<server>:<path>' \
    --argument-names input
    set -l servers (cat ~/.ssh/known_hosts | awk '{print $1}' | cut -d '@' -f 1 | sort -u)
    set -l server_part (string replace -r '^([^@]*)@([^:]*)' '$2' $input)
    set -l compl_prefix (string replace -r "$server_part\$" '' $input)
    for server in $servers
        echo "$compl_prefix$server:"
    end
end

function __complete_ssh_paths \
    --description 'Complete <path> part in ssh addresses with format <username>@<server>:<path>' \
    --argument-names input
    set -l input_list (string split ":" $input)
    if test (count $input_list) -ne 2
        return
    end

    set -l user_server $input_list[1]
    set -l path_part $input_list[2]
    set -l path_glob "$path_part*" # glob to list files matching given path

    # If path does not start with '/', i.e. not root dir, prepend an extra '*'
    # to list paths that does not match given path at the beginning, e.g. if
    # given path is 'notes', we would want to list 'school_notes',
    # 'personal_notes', etc. using glob '*notes*'.
    #
    # For hidden files things become tricky -- we cannot simply prepend '*' on
    # the given path, instead we have to insert it after the fist '.' for `ls`
    # to list hidden paths, e.g. for '.rc' we would want to list '.bashrc',
    # '.zshrc', '.vimrc' using glob '.*rc*'.
    if string match -qr '^\.' -- $path_part
        set path_glob ".*$(string sub -s 2 -- $path_glob)"
    else if string match -qvr '^/' -- $path_part
        set path_glob "*$path_glob"
    end

    set -l compl_prefix (string replace -r "$path_part\$" '' $input)
    set -l paths (command ssh $user_server "ls -Adp $path_glob" 2>/dev/null)
    for path in $paths
        echo "$compl_prefix$path"
    end
end

function __complete_ssh \
    --description 'Complete ssh addresses in the format of <username>@<server>:<path>'
    set -l input (commandline -ct)

    # Try complete with ssh addresses, if it matches the format;
    # otherwise, complete with local paths
    if string match -q "*@*" -- $input
        string match -q "*@*:*" -- $input
        and __complete_ssh_paths $input
        or __complete_ssh_servers $input
    else
        __fish_complete_path $input
    end
end
