# requires: miscell for kill-from-ports

# phase 1: while we have kube installed
function scrub-kube-leftovers-1a() {
    systemctl stop kubelet
    systemctl disable kubelet
    # trash manifests
    rm -rf /etc/kubernetes/manifests
    # if it exists, this file will keep konnectivity-server from running
    # with a 'bind: address already in use'
    # even when no process is has bound that before
    rm -f /etc/kubernetes/konnectivity-server/*.socket

    echo y | kubeadm reset -f
}

function scrub-kube-leftovers-1b() {
    # kill processes
    kubeadm init phase preflight
    # spot live ports and use pids-from-ports to kill related processes
    kill-from-ports 6443 10250 2379 2380

    # containers and images
    crictl ps -o yaml | grep ' id: ' | cut -d: -f2 | xargs crictl stop
    crictl ps -a -o yaml | grep ' id: ' | cut -d: -f2 | xargs crictl rm
    #crictl stop id1 id2...
    crictl rmi --prune

}

function scrub-kube-leftovers-2() {
    # remove rpms to ensure we get the ones from kube-install.sh next time
    #dnf module list cri-o | fgrep '[e]'
    rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd /root/.kube
    rm -rf /var/log/containers /var/log/pods
    rm -rf /usr/lib/firewalld/services/kube* /var/cache/dnf/kube*
    dnf clean all
}

# actually uninstall
function scrub-kube-leftovers-3() {
    type kubectl >& /dev/null || echo "rpm -aq | grep kube | xargs rpm -e"
    rpm -aq | egrep 'kubelet-|kubeadm-|kubectl-|cri-o-' | xargs rpm -e
}

function check-scrub-kube () {
    echo ========================= rpms
    rpm -aq | egrep 'kube|cri-o'

    echo ========================= crictl containers
    crictl ps -a

    echo ========================= crictl images
    crictl rmi --prune
    crictl images

    echo ========================= sockets
    ss --cgroup | grep kube

    echo ========================= kube manifests and sockets
    ls -l /etc/kubernetes/manifests /etc/kubernetes/**/*.socket

    echo ========================= systemd kubelet
    systemctl is-enabled kubelet
    systemctl is-active kubelet

    echo ========================= file-system files named in '*kube*' and '*etcd*'
    find / | grep kube | egrep -v '/home/|/usr/share/kube-ins'
    find / | grep etcd | egrep -v '/root/go/pkg|x-netcdf.xml|/usr/share/kube-ins'
}

##############
# test strategy is
# w2: master
# w3: regular worker
# fitxx: some FIT node

# use e.g.
# set-fitnode 06
# to choose which one is currently available for that test

function set-fitnode() {
    local arg="$1"; shift
    arg=$(sed -e s/fit// <<< $arg)
    export FITNODE=fit$(printf "%02d" $arg)
}
function check-fitnode() {
    [[ -z "$FITNODE" ]] && { echo "use command e.g. 'set-fitnode 19' to define your FIT node"; return 1; }
    return 0
}


# kick the test pod on each of the 3 nodes
function start-testpods() {
    local nodes="$@"
    check-fitnode || return 1
    [[ -z "$nodes" ]] && nodes="sopnode-w2.inria.fr sopnode-w3.inria.fr $FITNODE"
    local node
    for node in $nodes; do
        ssh root@$node kube-install.sh testpod
    done
}


# the test pod on the local box
function local-pod() {
    local key=$(hostname | sed -e s/sopnode-// -e 's/\.inria.fr//')
    echo fping-$key-pod
}

# find all the pod IPs in the namespace
function default-namespace-pod-ips() {
    kubectl get pod -o yaml | \
     yq '.items[].status.podIP'
}
# find all the pod names in the namespace
# xxx works but not used yet
# function default-namespace-pod-names() {
#     kubectl get pod -o yaml | \
#      yq '.items[].metadata.name'
# }
# find all the pod names+IPs in the namespace
# xxx not ready - can't figure out to
# produce this simply using yq
# function default-namespace-pod-names-ips() {
#     kubectl get pod -o yaml | \
#      yq '.items[].metadata.name'
# }


# run ping from one pod to some provided IP addresses
# which default to the IPs of all pods in the current namespace
function -check-pings() {
    local source="$1"; shift
    local dests="$@"
    [[ -z "$dests" ]] && dests=$(default-namespace-pod-ips)
    local ok="true"

    local dest
    for dest in $dests; do
        local ip=$(pod-ip $dest)
        [[ -z "$ip" ]] && ip=$dest
        echo -n ====== FROM $source to $dest = $ip" -> "
        local command="ping -c 1 -w 2 $ip"
        local success=OK
        exec-in-container-from-podname $source $command >& /dev/null
        [[ $? == 0 ]] && echo OK || { echo KO; ok=""; success=KO; }
        -log-line check-ping $source $dest $success
    done
    [[ -n "$ok" ]] && return 0 || return 1
}
# default
function check-pings() { -check-pings $(local-pod) "$@"; }


# solve DNS names from a pod
# hard-wired defaults for the names
function -check-dnss() {
    local source="$1"; shift
    local names="$@"
    [[ -z "$names" ]] && names="kubernetes faraday.inria.fr github.com"
    local ok="true"

    local name
    for name in $names; do
        echo ====== FROM $source resolving $name" -> "
        command="host $name"
        local success=OK
        exec-in-container-from-podname $source $command
        [[ $? == 0 ]] && echo OK || { echo KO; ok=""; success=KO; }
        -log-line check-dns $source $name $success
    done
    [[ -n "$ok" ]] && return 0 || return 1
}
function check-dnss() { -check-dnss $(local-pod) "$@"; }


# open http(s) TCP connections to well-known https services
function -check-https() {
    local source="$1"; shift
    local webs="$@"
    [[ -z "$webs" ]] && webs="r2lab.inria.fr github.com 140.82.121.4 faraday.inria.fr"
    local ok="true"

    local web
    for web in $webs; do
        echo ====== FROM $source opening a HTTP conn to $web:443 " -> "
        command="nc -z -v -w 3 $web 443"
        local success=OK
        exec-in-container-from-podname $source $command
        [[ $? == 0 ]] && echo OK || { echo KO; ok=""; success=KO; }
        -log-line check-http $source $web $success
    done
    [[ -n "$ok" ]] && return 0 || return 1
}
function check-https() { -check-https $(local-pod) "$@"; }


# test kubectl logs
function check-logs() {
    # from the root context this time
    local pods="$@"
    check-fitnode || return 1
    [[ -z "$pods" ]] && pods="fping-w2-pod fping-w3-pod fping-$FITNODE-pod"
    local ok="true"

    local pod
    for pod in $pods; do
        echo -n ====== GETTING LOG for $pod " -> "
        command="kubectl logs -n default $pod --tail=3"
        echo $command
        local success=OK
        $command
        [[ $? == 0 ]] && echo OK || { echo KO; ok=""; success=KO; }
        -log-line check-log $(hostname -s) $pod $success
    done
    [[ -n "$ok" ]] && return 0 || return 1
}


# test kubectl exec
function check-execs() {
    # from the root context this time
    local pods="$@"
    check-fitnode || return 1
    [[ -z "$pods" ]] && pods="fping-w2-pod fping-w3-pod fping-$FITNODE-pod"
    local ok="true"

    local pod
    for pod in $pods; do
        echo -n ====== EXECing in $pod " -> "
        command="kubectl exec -n default $pod -- hostname"
        echo $command
        local success=OK
        $command
        [[ $? == 0 ]] && echo OK || { echo KO; ok=""; success=KO; }
        -log-line check-exec $(hostname -s) $pod $success
    done
    [[ -n "$ok" ]] && return 0 || return 1
}

function check-all() {
    check-pings &
    check-dnss &
    check-https &
    check-logs &
    check-execs &
}


# run one of thoses tests repetitively
# store stats in a file named ~/TESTS.csv
# with a format like this
# DATE;test_function;FROM;TO;SUCCESS
function -log-line() {
    local test_function="$1"; shift
    local from="$1"; shift
    local to="$1"; shift
    local success="$1"; shift

    local hostname=$(hostname -s)
    local date=$(date "+%Y-%m-%d:%H:%M:%S")

    echo "${test_function};${from};${to};${success};${date}" >> ~/TESTS.csv
}

# run one of thoses tests repetitively
# store stats in a file named ~/TESTS.csv
# with a format like this
# test_function;LOCALHOSTNAME;FITNODE;SUCCESS;DATE;kubeadmRPMINFO
function -run-n-times() {
    local test_function="$1"; shift
    local count="$1"; shift
    local period="$1"; shift

    local counter=1
    while [[ $counter -le $count ]]; do
        echo "$test_function ${counter}/${count}"
        local success=OK
        $test_function || success=KO
        -log-line $test_function $(hostname -s) ALL $success
        sleep $period
        counter=$(($counter +1))
    done
}

# how many time do we try to run all the tests
function run-all() {
    local how_many="$1"; shift
    local period="$1"; shift
    [[ -z "$how_many" ]] && how_many=30
    [[ -z "$period" ]] && period=5
    -run-n-times check-all $how_many $period
}

function clear-logs() {
    rm -f ~/TESTS.csv
}
