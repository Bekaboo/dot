function issubdir \
        --description 'Check if a directory is a subdirectory of another'
    if test (count $argv) -ne 2
        echo "Usage: issubdir <sub_dir> <parent_dir>"
        return 1
    end

    if not test -d "$argv[1]"; or not test -d "$argv[2]"
        return 1
    end

    set -l subdir_realpath (realpath "$argv[1]")
    set -l parent_realpath (realpath "$argv[2]")
    return (string match -q -r -- "$parent_realpath/*" "$subdir_realpath")
end
