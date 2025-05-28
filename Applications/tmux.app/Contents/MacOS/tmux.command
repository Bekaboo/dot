#!/usr/bin/env sh --login
# vim: ft=sh ts=4 sw=4 sts=4 et :
#
# Launch tmux with default terminal on macOS
#
# macOS does not pass envvars defined in `~/.profile` (e.g. `FZF_DEFAULT_OPTS`)
# to GUI apps, so use login shell to forcibly source profile and make them
# available for tmux

(tmux ls 2>/dev/null | grep -vq attached) && [ "$PWD" = "$HOME" ] &&
	tmux at ||
	tmux
