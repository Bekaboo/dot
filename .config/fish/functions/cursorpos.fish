# Adapted from: https://unix.stackexchange.com/a/183121
# The function:
# 1. Switches terminal to raw mode (byte-by-byte, no echo) for reading ANSI response
# 2. Then send the ANSI escape sequence CSI 6 n (Device Status Report) to the terminal.
# 3. The terminal responds by writing the cursor position back to stdin in the format \033[row;colR.
# 4. Use perl to read and parse terminal response containing cursor position
function cursorpos --description 'Get current cursor position'
    set -l tty_settings (stty -g)

    stty raw -echo
    printf '\033[6n' >/dev/tty
    # Read stdin byte-by-byte until 'R' terminator via a single perl process
    # (avoids spawning dd per char, which is slow on macOS)
    perl -e 'while(sysread(STDIN,$c,1)){$_.=$c;last if$c eq"R"}print"$1\n"if/(\d+;\d+)/' </dev/tty

    stty $tty_settings
end
