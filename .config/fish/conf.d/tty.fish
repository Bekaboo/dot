# TTY Terminal Colors
if not status is-interactive; or test $TERM != linux
    return
end

echo -en "\e]P00D0C0C" #black
echo -en "\e]P1C4746E" #darkred
echo -en "\e]P28A9A7B" #darkgreen
echo -en "\e]P3D2B788" #brown
echo -en "\e]P48BA4B0" #darkblue
echo -en "\e]P5A292A3" #darkmagenta
echo -en "\e]P68EA4A2" #darkcyan
echo -en "\e]P7B4B3A7" #lightgrey
echo -en "\e]P87F827F" #darkgrey
echo -en "\e]P9E46876" #red
echo -en "\e]PA87A987" #green
echo -en "\e]PBDCA561" #yellow
echo -en "\e]PC7FB4CA" #blue
echo -en "\e]PD938AA9" #magenta
echo -en "\e]PE7AA89F" #cyan
echo -en "\e]PFB4B8B4" #white
clear #for background artifacting
