if not status is-interactive
    exit
end

# Spell fix abbreviation
set -g __spellfix_pairs \
    'ture true' \
    'Ture True' \
    'flase false' \
    'fasle false' \
    'Flase False' \
    'Fasle False' \
    'lcaol local' \
    'lcoal local' \
    'locla local' \
    'sahre share' \
    'saher share' \
    'balme blame'
function __spellfix_abbr_fn --description 'Fix spelling errors'
    # $argv: matched string
    set -l str "$argv"
    for pair_str in $__spellfix_pairs
        set -l pair (string split ' ' $pair_str)
        set pair[1] (string escape --style regex $pair[1])
        set pair[2] (string escape --style regex $pair[2])
        set pair[1] (string join '' '\b' $pair[1] '\b')
        set str (string replace --all --regex -- $pair $str)
    end
    echo -- $str
end

abbr --add spellfix --position anywhere \
    --regex '\S*' --function __spellfix_abbr_fn

# Command abbreviations
function __command_abbr --description 'Add an command abbreviation' -a trigger
    abbr --add $trigger --position command $argv[2..-1]
end

__command_abbr cl clear
__command_abbr cp 'cp -i'
__command_abbr df 'df -h'
__command_abbr fd 'fd -H -L'
__command_abbr fdfind 'fdfind -H -L'
__command_abbr free 'free -mh'
__command_abbr g git
__command_abbr d dot
__command_abbr lc 'wc -l'
__command_abbr ll 'ls -lhA'
__command_abbr mkdir 'mkdir -p'
__command_abbr mv 'mv -i'
__command_abbr sudoe 'sudo -E'
__command_abbr tree 'tree -N'
__command_abbr x trash

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
