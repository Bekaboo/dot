#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc
export PATH="${HOME}/.local/bin:${HOME}/.scripts:${PATH}"
export MANPAGER=nvim-manpager
