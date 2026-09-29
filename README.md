## Dotfiles

<img src="https://github.com/Bekaboo/dot/assets/76579810/10d9aaa3-5385-449d-9592-c5cb483c1796">

<img src="https://github.com/Bekaboo/dot/assets/76579810/de5ea335-0b0d-43e6-a49c-edde82ca45f1">

My dotfiles on Linux (KDE Wayland) and macOS, with configs for:

- KDE Plasma
    - [Wallpapers](.local/share/wallpapers/)
    - [Splash screens](.local/share/plasma/look-and-feel)
    - [Shortcuts](.config/kglobalshortcutsrc)
    - [Klassy](.config/klassy/klassyrc)
- [Yabai](.config/yabai)
- [Vim](.vimrc)
- [Neovim](.config/nvim)
- [Tmux](.config/tmux/)
- [Fish](.config/fish/)
- [Bash](.bashrc)
- [Alacritty](.config/alacritty/)
- [Kitty](.config/kitty/)
- [Wezterm](.config/wezterm/)
- [Foot](.config/foot/)
- ...

### Environment Variables

- `$DOT_DIR`: set this to indicate the path to the bare repo for dotfiles. Used
  in bash, fish, and nvim config to detect the dotfiles bare repo. If you use
  `git clone --bare <url> "$HOME/.dot"` to clone this repo, you should set it
  to `$HOME/.dot`
