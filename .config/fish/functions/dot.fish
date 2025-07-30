function dot \
    --wraps git \
    --description 'Manage dot files under home directory'
    git --git-dir=$HOME/.dot/ --work-tree=$HOME $argv
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

# Prevent accidental commit without pre-commit hooks
set -l precommit_hook "$HOME/.dot/hooks/pre-commit"
if not test -e "$precommit_hook"
    echo "#!/usr/bin/env sh
if [ -e \"$precommit_hook\" ] && [ \"\$0\" != \"$precommit_hook\" ]; then
    exit 0
fi
echo '`pre-commit` not installed, you should:'
echo '1. Install `pre-commit` command following https://pre-commit.com/'
echo '2. Enable it in dot repo with `GIT_DIR=\"\$HOME/.dot\" GIT_WORK_TREE=\"\$HOME\" pre-commit install -f`'
exit 1" >$precommit_hook
    chmod +x $precommit_hook
end
