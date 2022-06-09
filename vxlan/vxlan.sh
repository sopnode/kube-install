# based on
# https://joejulian.name/post/how-to-configure-linux-vxlans-with-multiple-unicast-endpoints/

# howto
# * tweak the N1 N2 variables
# * copy-paste the whole file in the 2 nodes
# * run node1 on node #1 and node2 on node #2
# * run test-vxlan1 on node #1 or test-vxlan2 on node #2

# settings
# 192.168.3.x is the control network
# 10.0.0.x is the CIDR that we try to interconnect

# the numbers of the FIT nodes used
N1=1
N2=2

ID=100

# to inspect an interface in more depth, do e.g.
#ip -d link show vxlan0

function -node() {
    local thisip="$1"; shift
    local otherip="$1"; shift

    # Create a point-to-point VXLAN interface
    ip link add vxlan type vxlan id $ID dstport 4789 dev control

    bridge fdb append to 00:00:00:00:00:00 dst 192.168.3.$otherip dev vxlan

    ip addr add 10.0.0.$thisip/24 dev vxlan

    # Bring up the VXLAN interface
    ip link set dev vxlan up

}

function node1() { -node $N1 $N2; }
function node2() { -node $N2 $N1; }

function -test-vxlan() {
    local thisip="$1"; shift
    local otherip="$1"; shift
    # From the mcdonalds namespace, ping the 10.1.0.1 interface on the other node.
    # You should receive a reply.
    echo raw-vxlan connectivity
    ping "$@" 10.0.0.$otherip
}

function test-node1() { -test-vxlan $N1 $N2 "$@"; }
function test-node2() { -test-vxlan $N2 $N1 "$@"; }

function dump-vxlan() { tcpdump -i vxlan; }
function dump-control() { tcpdump -i control not port 22; }
