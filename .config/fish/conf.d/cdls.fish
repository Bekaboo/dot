function __dirchanged \
        --on-variable PWD \
        --description 'List directory contents after changing cwd'
    set -l tcols (tput cols)
    set -l max_lines (math ceil (tput lines) / 4)
    set -l num_lines (count (ls -C --width=$tcols))
    if test $num_lines -le $max_lines
        ls --color=auto
    else
        ls -C --color --width=$tcols | head -n $max_lines
        echo
        echo ... $num_lines lines total
    end
end
