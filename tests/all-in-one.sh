#!/bin/bash

# this script is used to launch the end-to-end tests
# encompassing 2 worker nodes on the wired side
# and 2 FIT nodes
#
# it will:
# load the kubernetes on the FIT nodes
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

S=inria_sopnode
RLOAD=""
RUNS=3
PERIOD=2
IMAGE=kubernetes
WITH_WORKER=true


# defaults set below - see set-*
FITNODE=
LEADER=
WORKER=
PROD=
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
    fitnode=$(sed -e s/fit// <<< $fitnode)
    fitnode=$(expr "$fitnode")
    local zid=$(printf "%02d" $fitnode)
    FITNODE=fit${zid}
    F=root@$FITNODE
}
function set-fitnode2() {
    local fitnode="$1"; shift
    fitnode=$(sed -e s/fit// <<< $fitnode)
    fitnode=$(expr "$fitnode")
    local zid=$(printf "%02d" $fitnode)
    FITNODE2=fit${zid}
    F2=root@$FITNODE2
}

set-leader w2
set-worker w3
set-fitnode 1
set-fitnode2 2

function check-config() {
    echo LEADER=$LEADER
    echo WORKER=$WORKER
    echo FITNODE=$FITNODE
    echo FITNODE2=$FITNODE2
    echo IMAGE=$IMAGE
    echo RUNS=$RUNS
    echo PERIOD=$PERIOD
    echo -n "type enter to confirm (or control-c to quit) -> "
    read _
}

function load-image() {
    set -e
    ssh $S@faraday.inria.fr rhubarbe load -i $IMAGE $FITNODE $FITNODE2
    ssh $S@faraday.inria.fr rhubarbe wait $FITNODE $FITNODE2
    set +e
}

function -map() {
    local verb="$1"; shift
    for h in $L $W $F $F2; do
        ssh $h kube-install.sh $verb
    done
}

function refresh() {
    for h in $L $W; do
        ssh $h refresh
    done
    for h in $F $F2; do
        ssh $h kube-install.sh switch-branch devel \; kube-install.sh self-update
    done
    versions
}

function versions() { -map version; }

function leave() { -map leave-cluster; }

function create() {
    ssh $L kube-install.sh create-cluster
}

function join-wired() {
    ssh $W "kube-install.sh join-cluster r2lab@$LEADER"
}
function join-fitnodes() {
    for h in $F $F2; do
        ssh $h "kube-install.sh join-cluster r2lab@$LEADER"
    done
}
function leave-fitnodes() {
    for h in $F $F2; do
        ssh $h "kube-install.sh leave-cluster"
    done
}
function join() {
    join-wired
    join-fitnodes
}

function testpods() { -map testpod; }
function testpods2() { -map testpod2; }

function trashpods() {
    ssh $L "trash-testpods"
}

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
    local msg=dev
    [[ -n $PROD ]] && msg=prod
    SUMMARY="SUMMARY-${msg}-$(date +%m-%d-%H-%M-%S).csv"
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
        echo RUNNING STEP $step
        $step
    done
}

function setup() {
    local steps="refresh leave create join testpods testpods2"
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
    echo "  -o: (prod) use sopnode-l1 + sopnode-w1 (default=$LEADER $WORKER)"
    echo "  -w: (no-worker) do not use any worker node on the wired side"
    echo "subcommand 'setup' to rebuild everything - use -l if rload is needed"
    echo "subcommand 'run' to run the tests - after that use notebook draw-results-nb to visualize"
    echo "subcommand 'leave-join' - use after setup, checks for nodes that go and come back - semi auto for now"
    exit 1
}

main() {
    set-fitnode 1
    while getopts "f:F:li:r:p:ow" opt; do
        case $opt in
            f) set-fitnode $OPTARG;;
            F) set-fitnode2 $OPTARG;;
            l) RLOAD="true";;
            i) IMAGE=$OPTARG;;
            r) RUNS=$OPTARG;;
            p) PERIOD=$OPTARG;;
            o) set-leader l1; set-worker w1; PROD=true;;
            w) WITH_WORKER="";;
            \?) usage ;;
        esac
    done
    shift $(($OPTIND - 1))
    [[ -z "$@" ]] && usage

    [[ -n "$WITH_WORKER" ]] || set-worker

    check-config

    for subcommand in "$@"; do
        $subcommand
    done
}

main "$@"
