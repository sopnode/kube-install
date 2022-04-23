# echo a shortname and a hostname

function normalize-node() {
    local name="$1"; shift
    case "$name" in
        [lw][0-9]*)
            sed -e 's/\(..\).*/\1:sopnode-\1.inria.fr/' <<< "$name"
            ;;
        sopnode-[lw][0-9]*)
            sed -e 's/sopnode-\(..\).*/\1:sopnode-\1.inria.fr/' <<< "$name"
            ;;
        fit[0-9][0-9]*)
            sed -e 's/\(.....\).*/\1:\1/' <<< "$name"
            ;;
    esac
}
