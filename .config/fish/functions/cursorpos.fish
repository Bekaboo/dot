# https://unix.stackexchange.com/a/183121
function cursorpos --description 'Get current cursor position'
    set -l tty_settings (stty -g)

    stty raw -echo
    printf '\033[6n' >/dev/tty

    set -l response ""
    while true
        set -l char (dd bs=1 count=1 2> /dev/null)
        if test "$char" = R
            break
        end
        set response "$response$char"
    end

    # Restore terminal settings
    stty $tty_settings

    string replace -r '^[^\[]*\[' '' -- $response
end
