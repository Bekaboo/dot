function dot \
        --wraps 'git' \
        --description 'Manage dot files under home directory'
    git --git-dir=$HOME/.dot/ --work-tree=$HOME $argv
end

# Make sure that we don't show all untracked files in home directory, this
# is executed only once when the function is loaded
dot config --local status.showUntrackedFiles no
# Create remote branches (e.g. origin/master) on git fetch like normal repos
# See https://stackoverflow.com/questions/36410044/fetch-from-origin-in-bare-repository-in-git-does-not-create-remote-branch
dot config --local remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
