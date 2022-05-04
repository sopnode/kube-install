function load-all() {
    local dir=$(dirname $BASH_SOURCE)
    local loader=$(basename $BASH_SOURCE)
    cd $dir
    local files=$(ls *.sh)
    for file in $files; do
        [[ "$file" == "$loader" ]] && continue
        # echo loading $file
        source $file
    done
    cd - >& /dev/null
}

load-all
