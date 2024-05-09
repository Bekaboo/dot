# Spell fix abbreviation
set -g __spellfix_pairs \
    'ture true'   \
    'Ture True'   \
    'flase false' \
    'fasle false' \
    'Flase False' \
    'Fasle False' \
    'lcaol local' \
    'lcoal local' \
    'locla local' \
    'sahre share' \
    'saher share' \
    'balme blame' \

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
function __command_abbr --description 'Add an command abbreviation'
    # $argv[1]: trigger
    abbr --add $argv[1] --position command $argv[2..-1]
end

__command_abbr cmd         'command'
__command_abbr cp          'cp -i'
__command_abbr dc          'cd'
__command_abbr df          'df -h'
__command_abbr fd          'fd -H -L --mount'
__command_abbr fdfind      'fdfind -H -L --mount'
__command_abbr free        'free -m'
__command_abbr g           'git'
__command_abbr lc          'wc -l'
__command_abbr lzg         'lazygit'
__command_abbr lzgit       'lazygit'
__command_abbr mkdir       'mkdir -p'
__command_abbr mv          'mv -i'
__command_abbr nv          'nvim'
__command_abbr pip-install 'pip install --user'
__command_abbr r           'ranger'
__command_abbr sudoe       'sudo -E'
__command_abbr tree        'tree -N'
__command_abbr x           'trash'

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

abbr --add 'v' --position command --function __command_abbr_v_fn
