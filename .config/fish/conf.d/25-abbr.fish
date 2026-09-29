if not status is-interactive
    exit
end

# Command abbreviations
function __command_abbr --description 'Add an command abbreviation' -a trigger
    abbr --add $trigger --position command $argv[2..-1]
end

__command_abbr cl clear
__command_abbr d dot
__command_abbr g git
__command_abbr kc kubectl
__command_abbr ll 'ls -lhA'
__command_abbr tf terraform
__command_abbr x trash
__command_abbr xr trash-restore

function __command_abbr_v_fn --description 'Abbreviation function for `v`'
    if command -q nvim
        echo nvim
        return
    end
    if command -q vim
        echo vim
        return
    end
    echo vi
end

abbr --add v --position command --function __command_abbr_v_fn
