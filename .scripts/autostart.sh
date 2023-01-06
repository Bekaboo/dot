#!/usr/bin/env bash
# vim: ft=sh :

if command -v fusuma &>/dev/null && command -v xdotool &>/dev/null
then
    exec fusuma -d
fi
