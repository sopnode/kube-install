#!/bin/bash

LEADER=sopnode-w2.inria.fr
WORKER=sopnode-w3.inria.fr
FITNODE=fit01
RUNS=3
PERIOD=2

M=root@$LEADER
W=root@$WORKER
F=root@$FITNODE
S=inria_sopnode

function check-config() {
    echo LEADER=$LEADER
    echo WORKER=$WORKER
    echo FITNODE=$FITNODE
    echo RUNS=$RUNS
    echo PERIOD=$PERIOD
    echo -n "type enter to confirm (or control-c to quit) -> "
    read _
}

function load-image() {
    ssh $S@faraday.inria.fr rhubarbe load -i kubernetes $FITNODE
    ssh $S@faraday.inria.fr rhubarbe wait $FITNODE
}

function -map() {
    local verb="$1"; shift
    for h in $M $W $F; do
        ssh $h kube-install.sh $verb
    done
}

function refresh() {
    for h in $M $W; do
        ssh $h "source /root/diana/bash/comp-sopnode.ish; refresh"
    done
    ssh $F git -C kube-install pull
    versions
}

function versions() { -map version; }

function leave() { -map leave-cluster; }

function create() {
    ssh $M kube-install.sh create-cluster
    ssh $M kube-install.sh networking-calico-postinstall
}

function join() {
    for h in $W $F; do
        ssh $h "kube-install.sh join-cluster r2lab@$LEADER"
    done

    ssh $M "source /usr/share/kube-install/bash-utils/loader.sh; fit-label-nodes"
}

function testpods() { -map testpod; }

function trashpods() {
    ssh $M "source /usr/share/kube-install/bash-utils/loader.sh; trash-testpods"
}

function tests() {
    for h in $M $W; do
        echo "running $RUNS tests every $PERIOD s on $h"
        ssh $h "source /usr/share/kube-install/bash-utils/loader.sh; clear-logs; set-fitnode $FITNODE; run-all $RUNS $PERIOD"
    done
    echo "running $RUNS tests every $PERIOD s on $F"
    ssh $F "source /root/kube-install/bash-utils/loader.sh; clear-logs; join-tunnel; set-fitnode $FITNODE; run-all $RUNS $PERIOD"
}

function gather() {
    ./gather-logs.sh $FITNODE
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
function run()          { -steps check-config tests gather ; }

function usage() {
    echo "Usage: $0 subcommand_1 .. subcommand_n"
    echo "subcommand 'full-monty' to rebuild everything including rhubarbe-load"
    echo "subcommand 'setup' to rebuild everything except rhubarbe-load"
    echo "subcommand 'run' to run the tests"
    exit 1
}

while getopts "f:r:p:" opt; do
    case $opt in
        f) FITNODE=$OPTARG;;
        r) RUNS=$OPTARG;;
        p) PERIOD=$OPTARG;;
        \?) usage ;;
    esac
done
shift $(($OPTIND - 1))
[[ -z "$@" ]] && usage


for subcommand in "$@"; do
    $subcommand
done
