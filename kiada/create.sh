#!/bin/bash

source create-nodes.sh
source create-images.sh

DEFAULT_IMAGE=kiada
DEFAULT_NODE=$(hostname)
DEFAULT_RUN=true

function main() {
    local node=$DEFAULT_NODE
    local image=$DEFAULT_IMAGE
    local run=$DEFAULT_RUN
    while getopts "n:i:s" opt; do
        case $opt in
            n) node=$OPTARG;;
            i) image=$OPTARG;;
            s) run="";;
            \?) echo "Usage: $0 [-n node] [-i image] [-s]"; exit 1 ;;
        esac
    done

    local shortname=$(normalize-node $node | cut -d: -f1)
    local hostname=$(normalize-node $node | cut -d: -f2)
    local fullimage=$(normalize-image $image)

    # echo shortname=$shortname
    # echo hostname=$hostname
    # echo fullimage=$fullimage

    [[ -z "$shortname" || -z "$hostname" ]] && {
        echo something wrong with node $node;
        exit 1;
    }
    [[ -z "$fullimage" ]] && {
        echo something wrong with image $image;
        exit 1;
    }

    readonly template=kiada-l1.yaml
    readonly script=create.yq
# adding all capabilities because these are for tests only
# and typically a simple ping won't work out of the box
    cat > $script << EOF
.metadata.name = "${image}-${shortname}-pod"
|
.spec.containers[0].name = "${image}-${shortname}-cont"
|
.spec.containers[0].image = "${fullimage}"
|
.spec.nodeName = "${hostname}"
|
.spec.containers[0].securityContext.capabilities.add = [ "ALL" ]
EOF
    local yamlfile="${image}-${shortname}.yaml"
    yq --from-file $script $template > $yamlfile
    if [[ -z "$run" ]]; then
        echo $yamlfile
    else
        local command="kubectl apply -f $yamlfile"
        echo $command
        $command
    fi

}

main "$@"
