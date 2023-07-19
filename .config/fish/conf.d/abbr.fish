function __command_abbr --description 'Add an command abbreviation'
    # $argv[1]: trigger
    # $argv[2]: expansion
    abbr --add $argv[1] --position command $argv[2]
end

__command_abbr cp 'cp -i'
__command_abbr df 'df -h'
__command_abbr free 'free -m'
__command_abbr lc 'wc -l'
__command_abbr lzgit 'lazygit'
__command_abbr mv 'mv -i'
__command_abbr pip-install 'pip install --user'
__command_abbr tree 'tree -m'
__command_abbr nv 'nvim'
__command_abbr v 'nvim'
__command_abbr r 'ranger'
__command_abbr sudo 'sudo -E'
