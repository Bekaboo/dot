function dot \
    --wraps git \
    --description 'Manage dot files under home directory'
    git --git-dir=$DOT_DIR --work-tree=$HOME $argv
end

# Make sure that we don't show all untracked files in home directory, this
# is executed only once when the function is loaded
dot config --local status.showUntrackedFiles no

# Create remote branches (e.g. origin/master) on git fetch like normal repos
# See https://stackoverflow.com/questions/36410044/fetch-from-origin-in-bare-repository-in-git-does-not-create-remote-branch
dot config --local remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'

# Set the path to the root of the working tree, make vim-fugitive's
# `:Gdiffsplit` work
dot config --local core.worktree $HOME

# Fix error: 'warning: core.bare and core.worktree do not make sense' when
# using fugitive in nvim to stage files managed by dotfiles bare repo
# https://stackoverflow.com/questions/11856690/setting-the-work-tree-of-each-bare-repo
dot config --local core.bare false
