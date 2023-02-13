#!/bin/bash

FORCE=""

function build-if-not-present() {
    local image="$1"; shift
    local dir="$1"; shift
    local image_exists=""
    crictl inspecti localhost/$image >& /dev/null && image_exists=true
    [[ -n "$image_exists" && -z "$FORCE" ]] && {
        echo $image already present - ignored
        return
    }
    # we used to do buildah build but it seems outdated
    buildah bud -t $image $dir
}

[[ "$1" == "--force" ]] && FORCE=true

# the tests use only the ubuntu image
#build-if-not-present fedora-with-ping fping
build-if-not-present ubuntu-with-ping uping
