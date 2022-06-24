####
# using jsonpath is a little awkward, also wrt newlines, but not only
# so let's go for go templates instead

# find all the node names
export _GO_NODENAMES='{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}'
function k-nodes() {
    kubectl get nodes -o go-template --template "$_GO_NODENAMES"
}

#would work too
#export _GO_NODESTATUS='{{range .items}}{{.metadata.name}}:{{range .status.conditions}}{{.type}}={{.status}};{{end}}{{"\n"}}{{end}}'
export _GO_NODESTATUS='{{range .items}}{{.metadata.name}}:{{range .status.conditions}}{{if eq .type "Ready"}}{{.type}}={{.status}}{{end}}{{end}}{{"\n"}}{{end}}'
alias k-alives='kubectl get nodes -o go-template --template "$_GO_NODESTATUS" | grep "Ready=True" | cut -d: -f1'
alias k-deads='kubectl get nodes -o go-template --template "$_GO_NODESTATUS" | grep -v "Ready=True" | cut -d: -f1'

function calicoctl() { 
    local function="$1"; shift
    kubectl-calico $function --allow-version-mismatch "$@"
}
function get-pools() { kubectl calico --allow-version-mismatch get ippool "$@"; }
function watch-nodes() { watch kubectl get node "$@"; }
function watch-nodes-and-pools() {
    watch "echo ==== NODES; kubectl get nodes -o wide $@; echo ==== POOLS; kubectl-calico --allow-version-mismatch get ippools $@"
}
function watch-2() { watch-nodes-and-pools; }


function watch-pods() { watch kubectl get pod "$@"; }
function watch-pods-wide() { watch-pods -o wide "$@"; }
function watch-kube-pods() { watch-pods -n kube-system -o wide "$@"; }
function watch-all-pods() { watch-pods -A "$@"; }
function watch-all-pods-wide() { watch-all-pods -o wide "$@"; }
function watch-crictl() { watch crictl ps "$@"; }
function watch-everything() { watch kubectl get all -A "$@"; }
function watch-everything-wide() { watch-everything -o wide "$@"; }
function watch-services-and-pods() {
    watch "echo ==== PODS; kubectl get pod $@; echo ==== SVCS; kubectl get svc $@"
}
function watch-1() { watch-services-and-pods -A -o wide; }


function kube-default-namespace() {
    local new_ns=$1; shift
    kubectl config set-context --current --namespace=$new_ns
}
alias kdn=kube-default-namespace

####
function kube-summary() {
    echo ========================= rpm versions
    rpm -aq | egrep 'kube|cri-o'

    echo ========================= crictl images
    # keep non-intrusive
    # crictl rmi --prune
    crictl images

    echo ========================= systemd kubelet service
    systemctl is-enabled kubelet
    systemctl is-active kubelet

    echo ========================= crictl containers
    crictl ps -a

    [ -z "$@" ] && return

    echo ========================= sockets
    ss --cgroup | grep kube

    echo ========================= file-system files named in '*kube*' and '*etcd*'
    find / | grep kube | egrep -v '/home/|/usr/share/kube-ins'
    find / | grep etcd | egrep -v '/root/go/pkg|x-netcdf.xml|/usr/share/kube-ins'

    echo ========================= kube manifests and sockets
    ls -l /etc/kubernetes/manifests /etc/kubernetes/**/*.socket
}

function -ping-pod() {
    local pod="$1"; shift
    local ip=$(kubectl get -o yaml pod $pod | yq '.status.podIP')
    [[ -z "$ip" ]] && {
        >&2 echo "Cannot find podIP for pod $pod"
        echo unknown
        return 1
    }
    echo $ip
    ping -c 1 -w 1 $ip >& /dev/null
}

function ping-pods() {
    local pod
    local ip
    local message
    for pod in "$@"; do
        ip=$(-ping-pod $pod)
        if [[ $? == 0 ]]; then message=OK; else message=KO; fi
        echo "$pod ($ip) $message"
    done
}

function pod-names() {
    kubectl get pod "$@" -o yaml | yq '.items[].metadata.name'
}

function ping-all-pods() {
    ping-pods $(pod-names "$@")
}

function cri-ids() {
    local podname
    for podname in "$@"; do
        cri-id $podname
    done
}
function cri-id() {
    local podname="$1"; shift
    for contname in $podname $podname-cont $(sed -e s/-pod/-cont/ <<< $podname); do
        crictl ps --name $contname -o yaml | yq '.containers[0].id'
    done | grep -v null | sort | uniq
}

function -exec-in-container-from-podname() {
    local interactive="$1"; shift
    local podname="$1"; shift
    local cri_id=$(cri-id $podname)
    if [[ -z "$cri_id" ]]; then
        echo cri container not found for pod $podname
        return 1
    fi
    local exec_options=""
    if [[ "$interactive" == "yes" ]]; then
        exec_options="-ti"
    fi
    crictl exec $exec_options $cri_id "$@"
}

function exec-in-container-from-podname() {
    -exec-in-container-from-podname no "$@"
}
function enter-container-from-podname() {
    -exec-in-container-from-podname yes /bin/bash
}

function -pod-ip() {
    local podname="$1"; shift
    kubectl get pod $podname -o yaml 2> /dev/null | yq .status.hostIP | grep -v '^null$'
}
function pod-ip() {
    local podname="$1"; shift
    local alt="$podname-pod"
    -pod-ip $podname || -pod-ip $alt
}
