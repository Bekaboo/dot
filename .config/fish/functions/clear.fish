# Clear both screen and all previous outputs, works on Linux & macOS, see:
# https://stackoverflow.com/questions/2198377/how-can-i-clear-previous-output-in-terminal-in-mac-os-x

function clear --description 'Clear both screen and all previous outputs'
    printf '\33c\e[3J'
end
