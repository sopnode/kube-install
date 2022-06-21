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
# how to join the ISLAND network
ISLAND_FIT=10.3.3
ISLAND_SOPNODE=10.3.2
ISLAND_TUNNEL=10.3.1

function join-island-network() {
    local hostname=$(hostname -s)
    # with zero
    local zid=$(sed -e s,fit,, <<< $hostname)
    # without zero
    local id=$(printf %d $zid)
    local island_address=${ISLAND_FIT}.${id}
    if ip addr sh dev control | fgrep -q $island_address; then
        true
        # echo already joined the ISLAND network on $island_address
    else
        ip addr add ${island_address}/24 dev control
        ip route add ${ISLAND_TUNNEL}.0/24 dev control via 10.3.3.100
        ip route add ${ISLAND_SOPNODE}.0/24 dev control via 10.3.3.100
    fi
}


### test connectivity to the main pieces of the island
function test-island() {
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
    p1v 10.3.3.$id "fit${zid}"
    p1v 10.3.3.100 faraday
    p1v 10.3.2.50 sopnode-l1
    p1v 10.3.2.1 sopnode-w1
    p1v 10.3.2.2 sopnode-w2
    p1v 10.3.2.3 sopnode-w3
}


### compute local island IP
function island-local-ip() {
    local try1=$(ip addr sh dev control 2> /dev/null | grep $ISLAND_FIT | sed -e "s,/, ," | awk '{print $2}')
    [[ -n "$try1" ]] && { echo $try1; return 0; }
    local try2=$(ip addr sh dev eth0 2> /dev/null | grep $ISLAND_SOPNODE | sed -e "s,/, ," | awk '{print $2}')
    [[ -n "$try2" ]] && { echo $try2; return 0; }
    echo try1=">${try1}<"
    echo try2=">${try2}<"
}
