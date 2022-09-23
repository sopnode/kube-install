#!/bin/bash

source testpod-nodes.sh
source testpod-images.sh

DEFAULT_IMAGE=uping
DEFAULT_NODE=$(hostname)
DEFAULT_FORCE=
DEFAULT_RUN=true

function usage() {
    echo "Usage: $0 [-n node] [-i image] [-e ext] [-s] [-f]"
    echo " -s: create yaml file, but do not run"
    echo " -f: force creation of the yaml file even if already present"
    exit 1
}

function main() {
    local node=$DEFAULT_NODE
    local image=$DEFAULT_IMAGE
    local extension=""
    local run=$DEFAULT_RUN
    local force=$DEFAULT_FORCE
    while getopts "n:i:e:sf" opt; do
        case $opt in
            n) node=$OPTARG;;
            i) image=$OPTARG;;
            e) extension=$OPTARG;;
            s) run="";;
            f) force=true ;;
            \?) usage ;;
        esac
    done
    shift $(($OPTIND - 1))
    [[ -z "$@" ]] || usage

    local shortname=$(normalize-node $node | cut -d: -f1)
    local hostname=$(normalize-node $node | cut -d: -f2)
    local fullimage=$(normalize-image $image)

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
