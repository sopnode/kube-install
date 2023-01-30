#!/bin/bash

# this script is used to launch the end-to-end tests
# encompassing 2 worker nodes on the wired side
# and 2 FIT nodes
#
# it will:
# (optionnally) load the kubernetes on the FIT nodes
# make sure to pull kube-install to its latest version on all 4 nodes
# re-create the k8s cluster on the wired leader
# have all 4 nodes join that cluster
# launch 2 (ubuntu) test pods on each node
# and perform various tests in that environment
#
# the results are gathered in a SUMMARY-*.csv file
# and they can be interpreted/visualized by the
# notebook all-in-one-draw-results-nb.py
# (currently tailored for vs-code)

# what gets actually triggered on the various nodes
# is in general
# (*) either a call to kube-install.sh itself directly
# (*) or a function defined in ../bash-utils/sopnode-tests.sh
#     that gets shipped on the nodes as well

SLICE=inria_sopnode
RLOAD=""
RUNS=3
PERIOD=2
IMAGE=kubernetes
WITH_WORKER=true
WITH_FIT=true


# defaults set below - see set-*
FITNODE=
LEADER=
WORKER=
PRESET=dev
# shortcuts root@ on each box
L=
W=
F=
F2=

function set-leader() {
    local leader="$1"; shift
    leader=$(sed -e s/sopnode-// -e 's/\.inria.fr//' <<< $leader)
    LEADER=sopnode-${leader}.inria.fr
    L=root@$LEADER
}

function set-worker() {
    local worker="$1"; shift
    worker=$(sed -e s/sopnode-// -e 's/\.inria.fr//' <<< $worker)
    if [[ -z "$worker" ]]; then
        echo "NO WORKER used in this test"
        WORKER=""
        W=""
    else
        WORKER=sopnode-${worker}.inria.fr
        W=root@$WORKER
    fi
}

function set-fitnode() {
    local fitnode="$1"; shift
    if [[ -z "$fitnode" ]]; then
        echo "NO FIT NODE used in this test"
        FITNODE=""
        F=""
    else
        fitnode=$(sed -e s/fit// <<< $fitnode)
        fitnode=$(expr "$fitnode")
        local zid=$(printf "%02d" $fitnode)
        FITNODE=fit${zid}
        F=root@$FITNODE
    fi
}
function set-fitnode2() {
    local fitnode="$1"; shift
    if [[ -z "$fitnode" ]]; then
        FITNODE2=""
        F2=""
    else
        fitnode=$(sed -e s/fit// <<< $fitnode)
        fitnode=$(expr "$fitnode")
        local zid=$(printf "%02d" $fitnode)
        FITNODE2=fit${zid}
        F2=root@$FITNODE2
    fi
}

set-leader w2
set-worker w3
set-fitnode 1
set-fitnode2 2

function check-config() {
    echo "----"
    echo SLICE=$SLICE
    echo "----"
    if [[ -n "$RLOAD" ]]; then
        echo IMAGE=$IMAGE
    else
        echo no image loaded
    fi
    echo "----"
    echo LEADER=$LEADER
    echo WORKER=$WORKER
    echo FITNODE=$FITNODE
    echo FITNODE2=$FITNODE2
    echo "----"
    echo RUNS=$RUNS
    echo PERIOD=$PERIOD
    echo -n "type enter to confirm (or control-c to quit) -> "
    read _
}

function load-image() {
    set -e
    ssh $SLICE@faraday.inria.fr rhubarbe load -i $IMAGE $FITNODE $FITNODE2
    ssh $SLICE@faraday.inria.fr rhubarbe wait $FITNODE $FITNODE2
    set +e
}

function -map-some() {
    local verb="$1"; shift
    for h in "$@"; do
        echo ======== MAP: $h: invoking verb ${verb}
        ssh $h kube-install.sh $verb
    done
}

function -map-all() {
    local verb="$1"; shift
    -map-some $verb $L $W $F $F2
}

function self-update() {
    -map-some self-update $L $W
    -map-some "switch-branch devel" $F $F2
    -map-some self-update $F $F2
}

function versions() { -map-all version; }

function leave() {
    -map-some leave-cluster $W $F $F2
}
function destroy() {
    -map-some destroy-cluster $L
}
function create() {
    -map-some create-cluster $L
}

function join() {
    -map-some "join-cluster r2lab@$LEADER" $W $F $F2
}
function enable-multus() {
    -map-some enable-multus $L
}

function multus-network-attachments() {
    -map-some multus-network-attachments $L
}

function testpods() { -map-all testpod; }
function testpods2() { -map-all testpod2; }
function testpods-multus() { -map-all testpod-multus; }

function trashpods() { ssh $L trash-testpods; }

function tests() {
    # join-tunnel is recommended, although not crucial
    # it only matters if you need a route from the fit node to the ipip tunnel endpoints
    for h in $F $F2; do
        ssh $h join-tunnel
    done

    for h in $L $W $F $F2; do
        echo "running $RUNS tests every $PERIOD s on $h"
        ssh $h "clear-logs; set-leader $LEADER; set-worker $WORKER; set-fitnode $FITNODE; set-fitnode2 $FITNODE2; run-all $RUNS $PERIOD; log-rpm-versions"
    done
}

function gather() {
    SUMMARY="SUMMARY-${PRESET}-$(date +%m-%d-%H-%M).csv"
    rm -f $SUMMARY

    for h in $L $W $F $F2; do
        rsync -ai $h:TESTS.csv GATHER-$h.csv
        cat GATHER-$h.csv >> $SUMMARY
    done

    cat << EOF
ipython
import postprocess
df1, df2, df2_straight, df2_cross = postprocess.load("$SUMMARY")
EOF
}

###

function -steps() {
    for step in $@; do
        echo ================ RUNNING STEP $step
        $step
    done
}

function setup() {
    local steps="self-update versions leave destroy create join enable-multus multus-network-attachments testpods testpods2 testpods-multus"
    [[ -n "$RLOAD" ]] && { steps="load-image $steps"; }
    -steps $steps
}
function run() {
    -steps tests gather
}

########## checking nodes that leave and join back

# usage:
# arg1=delay to wait in seconds (default to 120)
function check-fitnodes-are-ready() {
    local timeout="$2"; shift
    [[ -z "$timeout" ]] && timeout=120
    echo "checking for $fitnode to be ready in $L - timeout=$timeout"
    ssh $L kubectl wait --timeout="${timeout}s" node --for=condition=Ready $FITNODE $FITNODE2
    local retcod="$?"
    if [[ $retcod == 0 ]]; then
        echo node $FITNODE and $FITNODE2 are Ready
    else
        echo node $FITNODE and/or $FITNODE2 NOT Ready after $timeout s
    fi
    return $retcod
}

# assumed is a properly running cluster with the fitnode node attached
# i.e. referred to as 'reference state' in https://github.com/parmentelat/kube-install/issues/16
function leave-join-1() {
    echo "leave-join-1: cleanly removing nodes $FITNODE and $FITNODE2 from cluster"
    ssh $L kubectl drain --force --ignore-daemonsets $FITNODE $FITNODE2
    ssh $L kubectl delete node $FITNODE $FITNODE2
    echo "leave-join-1: $FITNODE and $FITNODE2 are leaving the cluster"
    leave-fitnodes
    echo "xxx should we use an artificcial delay here ?"
    echo "leave-join-1: $FITNODE and $FITNODE2 are joining the cluster again"
    join-fitnodes
    if check-fitnodes-are-ready; then
        echo leave-join-1 OK
    else
        echo leave-join-1 KO
    fi
}

function leave-join() { -steps leave-join-1; }

###

function usage() {
    echo "Usage: $0 [options] subcommand_1 .. subcommand_n"
    echo "Options:"
    echo "  -f 3: use fit03 for as the fit node (defaut=$FITNODE)"
    echo "  -F 4: use fit04 for as the fit node #2 (defaut=$FITNODE2)"
    echo "  -l: causes the FIT nodes to be rload'ed before anything else happens"
    echo "  -i kubernetes-f36: use that (faraday) image (default=$IMAGE)"
    echo "  -r 10: repeat the test 10 times (default=$RUNS)"
    echo "  -p 3: wait for 3 seconds between each run (default=$PERIOD)"
    echo "  -P prod: use sopnode-l1 + sopnode-w1 (default=$LEADER $WORKER)"
    echo "  -w: (no-worker) do not use any worker node on the wired side"
    echo "  -0: (0 radio) do not use any FIT node"
    echo "  -s slicename - default is $SLICE"
    echo "  -y: do not check-config"
    echo "subcommand 'setup' to rebuild everything - use -l if rload is needed"
    echo "subcommand 'run' to run the tests - after that use notebook draw-results-nb to visualize"
    echo "subcommand 'leave-join' - use after setup, checks for nodes that go and come back - semi auto for now"
    exit 1
}

function preset-dev() {
    set-leader w2
    set-worker w3
}

function preset-prod() {
    set-leader l1
    set-worker w1
}

function preset-w1-leader() {
    set-leader w1
    set-worker ""
}

main() {
    set-fitnode 1
    set-fitnode2 2
    while getopts "f:F:li:r:p:P:w0s:y" opt; do
        case $opt in
            f) set-fitnode $OPTARG;;
            F) set-fitnode2 $OPTARG;;
            l) RLOAD="true";;
            i) IMAGE=$OPTARG;;
            r) RUNS=$OPTARG;;
            p) PERIOD=$OPTARG;;
            P) PRESET=$OPTARG;;
            w) WITH_WORKER="";;
            0) WITH_FIT="";;
            s) SLICE=$OPTARG;;
            y) YES=true;;
            \?) usage ;;
        esac
    done
    shift $(($OPTIND - 1))

    local preset_func=preset-$PRESET
    type $preset_func >& /dev/null || { echo unknown preset $PRESET -- exiting; exit 1; }
    # call the preset to perform relevant init
    $preset_func
    [[ -n "$WITH_FIT" ]] || { set-fitnode; set-fitnode2; }

    [[ -n "$YES" ]] || check-config

    [[ -z "$@" ]] && usage

    local first="$1"; shift
    local log=all-in-one-log-$(date +%m-%d-%H-%M)-${first}.txt
    for subcommand in $first "$@"; do
        $subcommand
    done | tee $log
}

main "$@"
