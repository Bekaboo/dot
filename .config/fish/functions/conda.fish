fish_add_path /opt/miniconda3/bin

if not type -q conda
    exit 127
end

function conda --wraps conda --description 'Lazy load conda environment'
    command conda shell.fish hook | source; or return
    # After sourcing the hook script, function `conda` should be
    # replaced by the one defined in the hook script
    conda $argv
end
