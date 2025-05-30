complete -f -c macos-keymap

complete -c macos-keymap -s h -l help -d "Show help message"
complete -c macos-keymap -s r -l reset -d "Reset keyboard mapping to default"

# Vendor/Product ID arguments
complete -c macos-keymap -n "not __fish_contains_opt h help r reset" -d "Vendor ID" -a "(type -q hidutil; and hidutil list | awk '/Keyboard/{print \$1}')"
complete -c macos-keymap -n "not __fish_contains_opt h help r reset" -d "Product ID" -a "(type -q hidutil; and hidutil list | awk '/Keyboard/{print \$2}')"
