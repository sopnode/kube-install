#!/bin/bash

S=inria_sopnode
RUNS=3
PERIOD=2
IMAGE=kubernetes

# defaults set below - see set-*
FITNODE=
LEADER=
WORKER=
PROD=
# shortcuts root@ on each box
L=
W=
F=

function set-leader() {
    local leader="$1"; shift
    leader=$(sed -e s/sopnode-// -e 's/\.inria.fr//' <<< $leader)
    LEADER=sopnode-${leader}.inria.fr
    L=root@$LEADER
}

function set-worker() {
    local worker="$1"; shift
    worker=$(sed -e s/sopnode-// -e 's/\.inria.fr//' <<< $worker)
    WORKER=sopnode-${worker}.inria.fr
    W=root@$WORKER
}

function set-fitnode() {
    local fitnode="$1"; shift
    fitnode=$(sed -e s/fit// <<< $fitnode)
    fitnode=$(expr "$fitnode")
    local zid=$(printf "%02d" $fitnode)
    FITNODE=fit${zid}
    F=root@$FITNODE
}

set-leader w2
set-worker w3
set-fitnode 1

function check-config() {
    echo LEADER=$LEADER
    echo WORKER=$WORKER
    echo FITNODE=$FITNODE
    echo IMAGE=$IMAGE
    echo RUNS=$RUNS
    echo PERIOD=$PERIOD
    echo -n "type enter to confirm (or control-c to quit) -> "
    read _
}

function load-image() {
    ssh $S@faraday.inria.fr rhubarbe load -i $IMAGE $FITNODE
    ssh $S@faraday.inria.fr rhubarbe wait $FITNODE
}

function -map() {
    local verb="$1"; shift
    for h in $L $W $F; do
        ssh $h kube-install.sh $verb
    done
}

function refresh() {
    for h in $L $W; do
        ssh $h refresh
    done
    ssh $F kube-install.sh switch-branch devel
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
function join-fitnode() {
    ssh $F "kube-install.sh join-cluster r2lab@$LEADER"
}
function leave-fitnode() {
    ssh $F "kube-install.sh leave-cluster"
}
function join() {
    join-wired
    join-fitnode
}

function testpods() { -map testpod; }

function trashpods() {
    ssh $L "trash-testpods"
}

function tests() {
    # join-tunnel is recommended, although not crucial
    # it only matters if you need a route from the fit node to the ipip tunnel endpoints
    ssh $F join-tunnel

    for h in $L $W $F; do
        echo "running $RUNS tests every $PERIOD s on $h"
        ssh $h "clear-logs; set-leader $LEADER; set-worker $WORKER; set-fitnode $FITNODE; run-all $RUNS $PERIOD; log-rpm-versions"
    done
}

function gather() {
    local msg=dev
    [[ -n $PROD ]] && msg=prod
    SUMMARY="SUMMARY-${msg}-$(date +%m-%d-%H-%M-%S).csv"
    rm -f $SUMMARY

    for h in $L $W $F; do
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

function full-monty()   { -steps check-config load-image refresh leave create join testpods; }
function setup()        { -steps check-config            refresh leave create join testpods; }
function run()          { -steps check-config tests gather; }

########## checking nodes that leave and join back

# usage:
# arg1=delay to wait in seconds (default to 120)
function check-fitnode-is-ready() {
    local timeout="$2"; shift
    [[ -z "$timeout" ]] && timeout=120
    echo "checking for $FITNODE to be ready in $L - timeout=$timeout"
    ssh $L kubectl wait --timeout="${timeout}s" node --for=condition=Ready $FITNODE
    local retcod="$?"
    if [[ $retcod == 0 ]]; then
        echo node $FITNODE is Ready
    else
        echo node $FITNODE NOT READy after $timeout s
    fi
    return $retcod
}

# assumed is a properly running cluster with the fitnode node attached
# i.e. referred to as 'reference state' in https://github.com/parmentelat/kube-install/issues/16
function leave-join-1() {
    echo "leave-join-1: cleanly removing note $FITNODE from cluster"
    ssh $L kubectl drain --force --ignore-daemonsets $FITNODE
    ssh $L kubectl delete node $FITNODE
    echo "leave-join-1: $FITNODE is leaving the cluster"
    leave-fitnode
    echo "xxx should we use an artificcial delay here ?"
    echo "leave-join-1: $FITNODE is joining the cluster again"
    join-fitnode
    if check-fitnode-is-ready; then
        echo leave-join-1 OK
    else
        echo leave-join-1 KO
    fi
}

function leave-join() { -steps check-config; leave-join-1; }

###

function usage() {
    echo "Usage: $0 [options] subcommand_1 .. subcommand_n"
    echo "Options:"
    echo "  -f 2: use fit02 for as the fit node (defaut=$FITNODE)"
    echo "  -i kubernetes-f36: use that (faraday) image (default=$IMAGE)"
    echo "  -r 10: repeat the test 10 times (default=$RUNS)"
    echo "  -p 3: wait for 3 seconds between each run (default=$PERIOD)"
    echo "  -o: (prod) use sopnode-l1 + sopnode-w1 (default=$LEADER $WORKER)"
    echo "subcommand 'full-monty' to rebuild everything including rhubarbe-load"
    echo "subcommand 'setup' to rebuild everything except rhubarbe-load"
    echo "subcommand 'run' to run the tests - after that use notebook draw-results-nb to visualize"
    echo "subcommand 'leave-join' - use after setup, checks for nodes that go and come back - semi auto for now"
    exit 1
}

main() {
    set-fitnode 1
    while getopts "f:i:r:p:o" opt; do
        case $opt in
            f) set-fitnode $OPTARG;;
            i) IMAGE=$OPTARG;;
            r) RUNS=$OPTARG;;
            p) PERIOD=$OPTARG;;
            o) set-leader l1; set-worker w1; PROD=true;;
            \?) usage ;;
        esac
    done
    shift $(($OPTIND - 1))
    [[ -z "$@" ]] && usage


    for subcommand in "$@"; do
        $subcommand
    done
}

main "$@"
