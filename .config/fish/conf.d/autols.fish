if not status is-interactive
    exit
end

function __auto_ls \
    --on-variable PWD \
    --description 'List directory contents after changing cwd'
    set -l lines (tput lines 2>/dev/null; or 16)
    set -l max_lines (math ceil $lines / 4)
    set -l output (ls -C --color)
    set -l num_lines (count $output)
    if test "$num_lines" -le "$max_lines"
        printf '%s\n' $output
    else
        printf '%s\n' $output | head -n $max_lines
        echo
        echo ... $num_lines lines total
    end
end
