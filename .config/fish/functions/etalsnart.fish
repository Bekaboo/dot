function etalsnart --wraps 'trans -shell -b -no-auto :en' \
        --description 'Translate to English'
    trans -shell -b -no-auto :en $argv
end

