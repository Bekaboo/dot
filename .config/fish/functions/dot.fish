function dot \
        --wraps 'git --git-dir=$HOME/.dot/ --work-tree=$HOME' \
        --description 'Manage dot files under home directory'
    git --git-dir=$HOME/.dot/ --work-tree=$HOME $argv
end

# Make sure that we don't show all untracked files in home directory, this
# is executed only once when the function is loaded
dot config --local status.showUntrackedFiles no
