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


####
function add-route-if-needed() {
    local dest="$1"; shift
    # do nothing if already present
    ip route | grep -q ${dest} >& /dev/null && return 0
    ip route add $dest "$@"
}



function -island-network() {
    local verb="$1"; shift
    case $(hostname) in
        faraday*)
            ${verb}-island-faraday;;
        sopnode-l1*)
            ${verb}-island-l1;;
        fit*)
            ${verb}-island-fit;;
        sopnode*)
            ${verb}-island-sopnode;;
    esac
}
function join-island-network() { -island-network join; }
function leave-island-network() { -island-network leave; }

function join-island-faraday() {
    # ip/ip tunnel interface
    ip link add r2lab-sopnode type ipip local 138.96.16.97 remote 138.96.245.50
    ip addr add 10.3.1.3/24 dev r2lab-sopnode
    ip link set dev r2lab-sopnode up

    # routing
    # use the ipip tunnel for all nodes on the sopnode side
    ip route add 138.96.245.0/24 dev r2lab-sopnode
    # except for sopnode-l1 that needs to go through the default route
    # because otherwise the tunnel won't work !
    ip route add 138.96.245.50 via 138.96.16.110 dev internet
}
function leave-island-faraday() {
    ip route add 138.96.245.50 via 138.96.16.110 dev internet
    ip link del dev r2lab-sopnode download
}

function join-island-l1() {
    # ip/ip tunnel interface
    ip link add r2lab-sopnode type ipip local 138.96.245.50 remote 138.96.16.97
    ip addr add 10.3.1.2/24 dev r2lab-sopnode
    ip link set dev r2lab-sopnode up

    # routing
    ip route add 192.168.3.0/24 dev r2lab-sopnode
    # same on this side
    ip route add 138.96.16.97 via 138.96.245.250 dev eth0
}
function leave-island-l1() {
    ip route del 138.96.16.97 via 138.96.245.250 dev eth0
    ip link del dev r2lab-sopnode
}

function join-island-fit() {
    # the FIT side
    add-route-if-needed 138.96.245.0/24 dev control via 192.168.3.100
    add-route-if-needed 10.3.1.0/24 dev control via 192.168.3.100
}
function leave-island-fit() {
    ip route del 138.96.245.0/24 dev control via 192.168.3.100
    ip route del 10.3.1.0/24 dev control via 192.168.3.100
}

function join-island-sopnode() {
    # the SOPNODE side
    # the other side network
    add-route-if-needed 192.168.3.0/24 dev eth0 via 138.96.245.50
    # the tunnel
    add-route-if-needed 10.3.1.0/24 dev eth0 via 138.96.245.50
    # faraday, otherwise it goes through the usual gateway
    add-route-if-needed 138.96.16.97/32 dev eth0 via 138.96.245.50
}
function leave-island-sopnode() {
    ip route del 192.168.3.0/24 dev eth0 via 138.96.245.50
    ip route del 10.3.1.0/24 dev eth0 via 138.96.245.50
    ip route del 138.96.16.97/32 dev eth0 via 138.96.245.50
}



### test connectivity to the main pieces of the island
function island-test() {
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
    id=$(printf %d $id)
    local zid=$(printf %02d $id)
    p1v 192.168.3.$id "fit${zid}"
    p1v 138.96.16.97 faraday-pub
    p1v 192.168.3.100 faraday-priv
#    p1v 10.3.1.3 faraday-tun
    p1v 138.96.245.50 sopnode-l1-pub
#    p1v 10.3.1.2 sopnode-l1-tun
    p1v 138.96.245.51 sopnode-w1
    p1v 138.96.245.52 sopnode-w2
    p1v 138.96.245.53 sopnode-w3
}

for subcommand in "$@"; do
    $subcommand
done
