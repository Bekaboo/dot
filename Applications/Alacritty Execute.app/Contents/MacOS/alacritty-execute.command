#!/usr/bin/env sh -l
# shellcheck disable=SC2096 # macOS allows multiple parameters in shebang
# vim:ft=sh:ts=4:sw=4:sts=4:et:
#
# Enable Alacritty to open `*.command` files directly on macOS so that we can
# use it as the default terminal for the tmux app, see
# https://github.com/alacritty/alacritty/issues/4722

if [ "$#" -eq 0 ]; then
    alacritty "$@"
    exit
fi

alacritty -e "$@"
