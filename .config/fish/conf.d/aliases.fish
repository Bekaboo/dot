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
