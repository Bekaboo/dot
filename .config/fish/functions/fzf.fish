function fzf --wraps fzf \
    -d 'Wrapper of fzf with adaptive height and flexible preview layout'
    if type -q fzf-wrapper
        fzf-wrapper $argv
    else
        command fzf $argv
    end
end
