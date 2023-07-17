function conda --wraps conda --description 'Lazy load conda environment'
    set -l conda /opt/miniconda3/bin/conda
    if test -f $conda
        $conda shell.fish hook | source
            # After sourcing the hook script, function 'conda' should be
            # replaced by the one defined in the hook script
            and conda $argv
    end
end
