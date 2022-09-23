#!/bin/bash

DEFAULT_IMAGE=uping
DEFAULT_NODE=$(hostname)
DEFAULT_FORCE=
DEFAULT_RUN=true
DEFAULT_MULTUS=""



# echo the image name as in the yaml

function normalize-image() {
    local name="$1"; shift
    case "$name" in
        fping)  echo localhost/fedora-with-ping ;;
        uping)  echo localhost/ubuntu-with-ping ;;
    esac
}

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

function normalize-multus() {
    local hostname="$1"; shift
    case $hostname in
        f*) echo control ;;
        *) echo eth0 ;;
    esac
}


function usage() {
    echo "Usage: $0 [-n node] [-i image] [-e ext] [-s] [-f] [-m]"
    echo " -s: create yaml file, but do not run"
    echo " -f: force creation of the yaml file even if already present"
    echo " -m: add a multus-powered interface in pod"
    exit 1
}
function main() {
    local node=$DEFAULT_NODE
    local image=$DEFAULT_IMAGE
    local extension=""
    local run=$DEFAULT_RUN
    local force=$DEFAULT_FORCE
    local multus=$DEFAULT_MULTUS
    while getopts "n:i:e:sfm" opt; do
        case $opt in
            n) node=$OPTARG;;
            i) image=$OPTARG;;
            e) extension=$OPTARG;;
            s) run="";;
            f) force=true ;;
            m) multus=true ;;
            \?) usage ;;
        esac
    done
    shift $(($OPTIND - 1))
    [[ -z "$@" ]] || usage

    local shortname=$(normalize-node $node | cut -d: -f1)
    local hostname=$(normalize-node $node | cut -d: -f2)
    local fullimage=$(normalize-image $image)
    local multusinterface=$(normalize-multus $shortname)

    [[ -z "$shortname" || -z "$hostname" ]] && {
        echo "unknown / something wrong with node $node";
        exit 1;
    }
    [[ -z "$fullimage" ]] && {
        echo "unknown / something wrong with image $image";
        exit 1;
    }

    readonly template=testpod-template.yaml
    local yamlfile="${image}-${shortname}.yaml"
    [[ -n "$multus" ]] && yamlfile="${image}-multus-${shortname}.yaml"
    if [[ -f $yamlfile && -z "$force" ]]; then
        echo "$yamlfile already there - reusing"
    else
        readonly script=testpod.yq
        # adding all capabilities because these are for tests only
        # and typically a simple ping won't work out of the box
        cat > $script << EOF
        .metadata.name = "${image}${extension}-${shortname}-pod"
        |
        .spec.containers[0].name = "${image}-${shortname}-cont"
        |
        .spec.containers[0].image = "${fullimage}"
        |
        .spec.nodeName = "${hostname}"
        |
        .spec.containers[0].securityContext.capabilities.add = [ "ALL" ]
EOF
        yq --from-file $script $template > $yamlfile

        if [[ -n "$multus" ]]; then
            cat > $script << EOF
            .metadata.name = "multus${extension}-${shortname}-pod"
            |
            .metadata.annotations["k8s.v1.cni.cncf.io/networks"] = "macvlan-${multusinterface}"
            |
            .spec.containers[0].name = "multus${extension}-${shortname}-cont"
EOF
            yq --from-file $script --inplace $yamlfile
        fi
    fi

    if [[ -z "$run" ]]; then
        echo $yamlfile
    else
        local command="kubectl apply -f $yamlfile"
        echo $command
        $command
    fi
}

main "$@"
