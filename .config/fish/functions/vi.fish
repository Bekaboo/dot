function vi --wraps 'vi'
    if command -q vi
        command vi $argv
    else if type -q vim
        vim --clean $argv
    else if type -q nvim
        nvim --clean -u NONE -i NONE $argv
    else
        echo "No vi compatible editor found"
        return 1
    end
end
