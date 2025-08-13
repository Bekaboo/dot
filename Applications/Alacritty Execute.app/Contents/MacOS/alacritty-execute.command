#!/usr/bin/env sh -l
# shellcheck disable=SC2096 # macOS allows multiple parameters in shebang
# vim:ft=sh:ts=4:sw=4:sts=4:et:
#
# Enable Alacritty to open `*.command` files directly on macOS so that we can
# use it as the default terminal for the tmux app, see
# https://github.com/alacritty/alacritty/issues/4722

if [ "$#" -eq 0 ]; then
    # macOS will wait for shell script to finish, including the script itself
    # and all subprocess. This can be observed by opening a custom application
    # that runs a shell script in the Automator app and clicking the "Run"
    # button on the top right corner.
    #
    # In this way, the second terminal will only appear after the first one is
    # closed, preventing us from opening multiple terminals, e.g. we cannot
    # open multiple alacritty window for different tmux sessions.
    #
    # To workaround this, we use `nohup` and run the terminal process in the
    # background. For unknown reason, we also need to redirect `stdout` and
    # `stdin` to `/dev/null` to make macOS consider the script as finished
    # after launching alacritty.
    nohup alacritty "$@" >/dev/null 2>&1 &
    exit
fi

nohup alacritty -e "$@" >/dev/null 2>&1 &
