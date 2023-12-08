function __auto_ls \
        --on-variable PWD \
        --description 'List directory contents after changing cwd'
    if not type -q tput
        ls -C --color
        return
    end

    set -l lines (tput lines)
    set -l cols (tput cols)
    set -l max_lines (math ceil $lines / 4)
    set -l num_lines (count (ls -C --width=$cols))
    if test $num_lines -le $max_lines
        ls --color
    else
        ls -C --color --width=$cols | head -n $max_lines
        echo
        echo ... $num_lines lines total
    end
end
