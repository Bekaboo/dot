#!/usr/bin/env sh -l
# shellcheck disable=SC2096 # macOS allows multiple parameters in shebang, see
# https://www.shellcheck.net/wiki/SC2096
# vim:ft=sh:ts=4:sw=4:sts=4:et:
#
# Launch tmux with default terminal on macOS
#
# macOS does not pass envvars defined in `~/.profile` e.g. `$PATH`,
# `$FZF_DEFAULT_OPTS`, to GUI apps, so use login shell to forcibly source
# profile and make them available for tmux

if (tmux ls 2>/dev/null | grep -vq attached) && [ "$PWD" = "$HOME" ]; then
	tmux at
    exit
fi

tmux
