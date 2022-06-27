# based on
# https://joejulian.name/post/how-to-configure-linux-ipips-with-multiple-unicast-endpoints/

# howto
# * tweak the N1 N2 variables
# * copy-paste the whole file in the 2 nodes
# * run node1 on node #1 and node2 on node #2
# * run test-node1 on node #1

# settings
# 192.168.3.x is the control network
# 10.0.0.x is the CIDR that we try to interconnect

# the numbers of the FIT nodes used
N1=1
N2=2

# to inspect an interface in more depth, do e.g.
#ip -d link show vxlan0

function -node() {
    local thisip="$1"; shift
    local otherip="$1"; shift

    # Create a point-to-point ipip interface
    ip link add ipip type ipip local 192.168.3.$thisip remote 192.168.3.$otherip
    ip addr add 10.0.0.$thisip dev ipip

    # Use the -d flag with ip link to show the VTEP (control) linked to the ipip interface:

    # Bring up the ipip interface
    ip link set dev ipip up

    ip route add 10.0.0.0/24 dev ipip

}

function node1() { -node $N1 $N2; }
function node2() { -node $N2 $N1; }

function -test-node() {
    local thisip="$1"; shift
    local otherip="$1"; shift
    ping "$@" 10.0.0.$otherip
}

function test-node1() { -test-node $N1 $N2 "$@"; }
function test-node2() { -test-node $N2 $N1 "$@"; }

function dump-ipip() { tcpdump -i ipip; }
function dump-control() { tcpdump -i control not port 22; }
