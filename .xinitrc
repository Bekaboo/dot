#!/bin/sh

userresources=$HOME/.Xresources
usermodmap=$HOME/.Xmodmap
sysresources=/etc/X11/xinit/.Xresources
sysmodmap=/etc/X11/xinit/.Xmodmap

# merge in defaults and keymaps
if [ -f $sysresources ]; then
    xrdb -merge $sysresources
fi

if [ -f $sysmodmap ]; then
    xmodmap $sysmodmap
fi

if [ -f "$userresources" ]; then
    xrdb -merge "$userresources"
fi

if [ -f "$usermodmap" ]; then
    xmodmap "$usermodmap"
fi

# start some nice programs

if [ -d /etc/X11/xinit/xinitrc.d ] ; then
 for f in /etc/X11/xinit/xinitrc.d/?*.sh ; do
  [ -x "$f" ] && . "$f"
 done
 unset f
fi

[ -f /etc/xprofile ] && source /etc/xprofile
[ -f "$HOME/.xprofile" ] && source "$HOME/.xprofile"

# make capslock (long press) another ctrl
if command -v setxkbmap &> /dev/null; then
  setxkbmap -option ctrl:nocaps,shift:both_capslock
fi

# make capslock (short press) another escape
if command -v xcape &> /dev/null; then
  xcape -e Control_L=Escape
fi

# set keyboard delay and repeat rate
if command -v xset &> /dev/null; then
    xset r rate 240 80
fi

if command -v startplasma-x11 &> /dev/null; then
    export DESKTOP_SESSION=plasma
    exec startplasma-x11
fi
