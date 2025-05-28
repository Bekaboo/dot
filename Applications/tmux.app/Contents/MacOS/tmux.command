#!/usr/bin/env sh
# vim: ft=sh ts=4 sw=4 sts=4 et :
# Launch tmux with default terminal on macOS

# Append brew install path in case tmux is installed with it
export PATH=$PATH:/opt/homebrew/bin:/usr/local/bin

if (tmux ls 2>/dev/null | grep -vq attached) && [ "$PWD" = "$HOME" ]; then
	tmux at
else
	tmux
fi
