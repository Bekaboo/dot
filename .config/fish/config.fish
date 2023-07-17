# vim:ft=fish:ts=4:sw=4:sts=4:et:

if not status is-interactive
    return
end

set -g fish_greeting # Disable fish greeting message

#   Colors
set -g fish_color_autosuggestion            brblue  --italics
set -g fish_color_cancel                    --reverse
set -g fish_color_command                   magenta --bold
set -g fish_color_comment                   white
set -g fish_color_cwd                       green
set -g fish_color_cwd_root                  red
set -g fish_color_end                       green
set -g fish_color_error                     brred
set -g fish_color_escape                    yellow
set -g fish_color_hg_added                  green
set -g fish_color_hg_clean                  green
set -g fish_color_hg_copied                 magenta
set -g fish_color_hg_deleted                red
set -g fish_color_hg_dirty                  red
set -g fish_color_hg_modified               cyan
set -g fish_color_hg_renamed                magenta
set -g fish_color_hg_unmerged               red
set -g fish_color_hg_untracked              white
set -g fish_color_history_current           --bold
set -g fish_color_host                      normal
set -g fish_color_host_remote               yellow
set -g fish_color_normal                    normal
set -g fish_color_operator                  brcyan
set -g fish_color_param                     cyan
set -g fish_color_pwd                       magenta --background=blue    --bold
set -g fish_color_quote                     white
set -g fish_color_redirection               yellow
set -g fish_color_search_match              normal  --background=yellow
set -g fish_color_selection                 white   --background=brblack --bold
set -g fish_color_status                    black   --background=yellow
set -g fish_color_status_0                  black   --background=white
set -g fish_color_user                      brgreen
set -g fish_color_valid_path                green
set -g fish_color_vcs                       white   --background=blue
set -g fish_pager_color_completion          normal
set -g fish_pager_color_description         white
set -g fish_pager_color_prefix              normal  --bold               --underline
set -g fish_pager_color_progress            magenta --bold
set -g fish_pager_color_selected_background --reverse

alias sudo='sudo -E '
alias cp='cp -i'
alias mv='mv -i'
alias rm='trash'
alias ls='ls --color=auto'
alias l='ls --color=auto'
alias ll='ls -l --color=auto'
alias lc='wc -l'
alias df='df -h'        # human-readable sizes
alias free='free -m'    # show sizes in MB
alias tree='tree -N'    # Display Chinese characters
alias clip='xclip -sel clip'
alias lzgit='lazygit'
alias pip-install='pip install --user'
alias translate='trans -shell -b -no-auto :zh'
alias etalsnart='trans -shell -b -no-auto :en'
alias nv='nvim'
alias v='nvim'
alias vi='nvim --clean'
alias vs='vim-startuptime'
alias emacs='emacs -nw'
alias em='emacs -nw'
alias r='ranger'
alias winecfg-wechat='/opt/apps/com.qq.weixin.deepin/files/run.sh winecfg'
alias home-backup='borg create \
    --list -v \
    --exclude-from ~/.scripts/borg/exclude.txt \
    borg/home::{hostname}-{user}-{now:%Y-%m-%dT%H:%M:%S.%f} ~; \
    borg prune --list -d 60 -w 24 -m 24 -y 10 borg/home; \
    borg compact --cleanup-commits borg/home'
alias kde-restart='kquitapp5 plasmashell || kstart5 plasmashell'
alias kwin-restart='kwin_x11 --replace 2>/dev/null &'
alias clean-tmp='find /tmp -ctime +7 -exec rm -rf {} +'
alias plasma-save-current-session='qdbus org.kde.ksmserver /KSMServer saveCurrentSession'

function __dirchanged --on-variable PWD --description 'Action to perform when the working directory changes'
    ls --color=auto
end
