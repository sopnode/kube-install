#!/bin/bash

# helpers

function p1() {
    local box="$1"; shift
    ping -c1 -w1 $box >& /dev/null
}

function p1v() {
    local box="$1"; shift
    local message="$1"; shift
    p1 $box && echo "$message ($box) OK" || echo "$message ($box) KO"
}


# #### these work, but are not actually necessary
# function add-route-if-needed() {
#     local dest="$1"; shift
#     # /32 does not show up in the output of ip route
#     dest=$(sed -e 's,/32$,,' <<< $dest)
#     # do nothing if already present
#     ip route 2> /dev/null | grep -q ${dest} >& /dev/null && return 0
#     ip route add $dest "$@"
# }

# function del-route-if-needed() {
#     local dest="$1"; shift
#     # /32 does not show up in the output of ip route
#     dest=$(sed -e 's,/32$,,' <<< $dest)
#     # do nothing if already present
#     ip route 2> /dev/null | grep -q ${dest} >& /dev/null || return 0
#     ip route del $dest "$@"
# }



function -tunnel() {
    local verb="$1"; shift
    case $(hostname) in
        faraday*)
            ${verb}-tunnel-faraday;;
        sopnode-l1*)
            ${verb}-tunnel-l1;;
        fit*)
            ${verb}-tunnel-fit;;
        sopnode*)
            ${verb}-tunnel-sopnode;;
        *)
            echo ${verb}-tunnel not supported on host $(hostname);;
    esac
}
function join-tunnel() { -tunnel join; }
function leave-tunnel() { -tunnel leave; }

function create-routing-table() {
    local id="$1"; shift
    local name="$1"; shift
    grep -q "$name" /etc/iproute2/rt_tables >& /dev/null || echo "$id $name" >> /etc/iproute2/rt_tables
}

# 138.96.16.109  is aka faraday-tun.inria.fr
# 138.96.245.249 is aka sopnode-tun.inria.fr

function join-tunnel-faraday() {
    # ip/ip tunnel interface
    ip link add r2lab-sopnode type ipip local 138.96.16.97 remote 138.96.245.50
    ip addr add 138.96.16.109/28 dev r2lab-sopnode
    ip link set dev r2lab-sopnode up

    # routing; need to resort to source routing
    # because packets originating from either control or data
    # MUST go through the ipip tunnel EVEN if targetting sopnode-l1
    create-routing-table 100 from-private
    ip rule add from 192.168.2.0/24 table from-private
    ip rule add from 192.168.3.0/24 table from-private

    ip route add 192.168.2.0/24 dev data table from-private
    ip route add 192.168.3.0/24 dev control table from-private
    ip route add 138.96.245.0/24 dev r2lab-sopnode table from-private
    ip route add default via 138.96.16.110 dev internet table from-private

    # packets from faraday itself
    # use the ipip tunnel for all nodes on the sopnode side
    ip route add 138.96.245.0/24 dev r2lab-sopnode
    # except for sopnode-l1 of course, that needs to go through
    # the default route because otherwise the tunnel cannot work !
    ip route add 138.96.245.50/32 via 138.96.16.110 dev internet
    # this route seems a side effect of turning on r2lab-sopnode
    # and is most unfortunate; remove, (and just ignore it if it's not here)
    ip route del 138.96.16.96/28 dev r2lab-sopnode >& /dev/null
}
function leave-tunnel-faraday() {
    ip route del 138.96.245.50/32 via 138.96.16.110 dev internet
    ip route del 138.96.245.0/24 dev r2lab-sopnode

    ip route flush table from-private
    ip rule del from 192.168.2.0/24 table from-private
    ip rule del from 192.168.3.0/24 table from-private

    ip link del dev r2lab-sopnode

}

function join-tunnel-l1() {
    # ip/ip tunnel interface
    ip link add r2lab-sopnode type ipip local 138.96.245.50 remote 138.96.16.97
    ip addr add 138.96.245.249/24 dev r2lab-sopnode
    ip link set dev r2lab-sopnode up

    # routing - the whole point so we can reach the fit nodes
    ip route add 192.168.3.0/24 dev r2lab-sopnode
    ip route add 192.168.2.0/24 dev r2lab-sopnode

    # packets that go back to faraday go on r2lab-sopnode
    ip route add 138.96.16.97/32 via 138.96.245.250 dev eth0
    # make sure the return packets flow through the tunnel
    ip route add 138.96.16.109/32 dev r2lab-sopnode
    # likewise this route is spurrious and it must go
    ip route del 138.96.245.0/24 dev r2lab-sopnode >& /dev/null
}
function leave-tunnel-l1() {
    ip route del 138.96.16.97 via 138.96.245.250 dev eth0
    ip link del dev r2lab-sopnode
}

function join-tunnel-fit() {
    # the FIT side
    ip route add 138.96.245.0/24 dev control via 192.168.3.100
}
function leave-tunnel-fit() {
    ip route del 138.96.245.0/24 dev control via 192.168.3.100
}

function join-tunnel-sopnode() {
    # the SOPNODE side
    # the other side network
    ip route add 192.168.3.0/24 dev eth0 via 138.96.245.50
    ip route add 192.168.2.0/24 dev eth0 via 138.96.245.50
    # faraday, otherwise it goes through the usual gateway
    ip route add 138.96.16.97/32 dev eth0 via 138.96.245.50
}
function leave-tunnel-sopnode() {
    ip route del 192.168.3.0/24 dev eth0 via 138.96.245.50
    ip route del 192.168.2.0/24 dev eth0 via 138.96.245.50
    ip route del 138.96.16.97/32 dev eth0 via 138.96.245.50
}



### test connectivity to the main pieces of the tunnel
function test-tunnel() {
    # provide the fit number if from sopnode
    local id="$1"; shift
    if [[ -z "$id" ]]; then
        local hostname=$(hostname -s)
        local zid=$(sed -e s,fit,, <<< $hostname)
        if [[ "$zid" != "$hostname" ]]; then
            id=$zid
        else
            id=1
        fi
        echo using default id=$id
    fi
    id=$(sed -e s/fit// <<< $id)
    id=$(expr "$id")
    local zid=$(printf %02d $id)
    p1v 138.96.16.97 faraday-pub
    p1v 192.168.3.100 faraday-priv
    p1v 138.96.16.109 "faraday-tun (may not work from outside of tunnel)"
    p1v 138.96.245.50 sopnode-l1-pub
    p1v 138.96.245.249 sopnode-l1-tun
    p1v 138.96.245.51 sopnode-w1
    p1v 138.96.245.52 sopnode-w2
    p1v 138.96.245.53 sopnode-w3
    p1v 138.96.245.30 sopnode-pdu-bas
    echo "assuming fit01 is turned ON"
    p1v 192.168.3.$id "fit${zid} on 192.168.3.$id (must work)"
    p1v 192.168.2.$id "data${zid} on 192.168.2.$id (may fail on some nodes)"
}

for subcommand in "$@"; do
    $subcommand
done
