#!/bin/bash

FORCE=""

function build-if-not-present() {
    local image="$1"; shift
    local dir="$1"; shift
    local image_exists=""
    crictl inspecti lcocalhost/$image >& /dev/null || image_exists=true
    [[ -n "$image_exists" && -z "$FORCE" ]] && {
        echo $image already present - ignored
        return
    }
    buildah build -t $image $dir
}

[[ "$1" == "--force" ]] && FORCE=true

build-if-not-present fedora-with-ping fping
build-if-not-present ubuntu-with-ping uping
