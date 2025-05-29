function issubdir \
    --description 'Check if a directory is a subdirectory of another' \
    --argument-names sub parent
    if test (count $argv) -ne 2
        echo 'Usage: issubdir <sub_dir> <parent_dir>'
        return 1
    end

    if not test -d "$sub"; or not test -d "$parent"
        return 1
    end

    set -l subdir_realpath (realpath $sub)
    set -l parent_realpath (realpath $parent)
    return (string match -q -r -- $parent_realpath'/*' $subdir_realpath)
end
