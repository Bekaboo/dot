#!/usr/bin/env bash
# vim: ft=sh :

if command -v &>/dev/null && command -v xdotool &>/dev/null; then
    exec fusuma -d
fi
