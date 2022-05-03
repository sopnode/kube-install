########## pseudo docstrings
MYDIR=$(dirname $(readlink -f $BASH_SOURCE))

# the way this is installed on the sopnodes is
# (*) repo is cloned in /usr/share/kube-install
# (*) with a symlink in /usr/local/bin/kube-install.sh

# for the mac where readlink has no -f option
[ -z "$MYDIR" ] && MYDIR=$(dirname $BASH_SOURCE)
[ -z "$_sourced_r2labutils" ] && source ${MYDIR}/r2labutils.sh

readonly MYDIR
cd $MYDIR

create-doc-category install "commands to make the node ready"
create-doc-category kube "commands to manage the kube cluster"
create-doc-category inspect "commands to check the installation"

DEFAULT_NETWORKING=calico

####
readonly USER=r2lab

###
function load-config() {
    local strict="$1"; shift

    # default for all
    export K8S_VERSION=1.23.6
    export CRIO_VERSION=1.22

    if [[ -n "$strict" ]]; then
        # spot the config file for that host
        local localconfig="$MYDIR/configs/$(hostname --short)-config.sh"
        [ -f $localconfig ] || {
            echo "local config $localconfig not found - bye"
            exit 1
        }

        # set -a / set +a is for exporting the variables
        set -a; source $localconfig; set +a
    fi
}

# function emergency-exit() {
#     echo EMERGENCY; exit 1
# }

# function breakpoint() {
#     echo -n "BREAKPOINT - type Enter when done ... "
#     read _
# }

##################################################### imaging

## references

### fedora

# our version: f35
# https://kubernetes.io/docs/setup/production-environment/container-runtimes/#cri-o
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

# still needed afterwards is tweaking your firewall

### miscell

# setting up konnectivity
# https://kubernetes.io/docs/tasks/extend-kubernetes/setup-konnectivity/
# (gives the gist of it, but a lot is implicit)

# using kubeadm with config files
# https://medium.com/@kosta709/kubernetes-by-kubeadm-config-yamls-94e2ee11244


# * silence apt install, esp. painful about kernel upgrades, that won't reboot on their own
# (as if it could reboot...)
export DEBIAN_FRONTEND=noninteractive

# all nodes
function prepare() {

    touch /etc/systemd/zram-generator.conf
    swapoff -a

    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
  modprobe -a $(cat /etc/modules-load.d/k8s.conf)

  cat <<EOF > /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables = 1
EOF
    sysctl -p /etc/sysctl.d/k8s.conf
}
doc-install prepare "miscell system-wide required settings"


function update-os() {
    [ -f /etc/fedora-release ] && dnf -y update
    [ -f /etc/lsb-release ]    && apt -y update
}
doc-install update-os "dnf or apt update"


function install() {
    install-k8s
    install-extras
    install-helm
}
doc-install install "meta-target to install k8s, extras and helm"

# all nodes
function install-extras() {
    [ -f /etc/fedora-release ] && dnf -y install git openssl netcat jq buildah
    [ -f /etc/lsb-release ]    && apt -y install git openssl netcat # jq
}
doc-install install-extras "useful tools"


# all nodes
function install-helm() {
    cd
    [ -f /etc/fedora-release ] && dnf -y install openssl
    curl -fsSL -o install-helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    bash install-helm.sh
    helm version
}
doc-install install-helm "install helm"


# all nodes
function install-k8s() {
    [ -f /etc/fedora-release ] || {
        $BASH_SOURCE is for fedora only
        exit 1
    }
    load-config
    fedora-install-k8s
    fetch-kube-images
}
doc-install install "install kubernetes core + images"

function fedora-install-k8s() {
    cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

    # Set SELinux in permissive mode (effectively disabling it)
    setenforce 0
    sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

    # K8S_VERSION and CRIO_VERSION defined in the configs/ file
    # for determining the available options:
    # K8S_VERSION: use dnf --showduplicates list kubelet --disableexcludes=kubernetes
    # CRIO_VERSION: use dnf module list cri-o

    [[ -z "$K8S_VERSION" || -z "$K8S_VERSION" ]] && {
        echo need to define K8S_VERSION and K8S_VERSION
        exit 1
    }

    echo using kube version $K8S_VERSION and cri-o version $CRIO_VERSION

    dnf -y --disableexcludes=kubernetes install kubelet-$K8S_VERSION kubeadm-$K8S_VERSION kubectl-$K8S_VERSION

    # too early !
    # systemctl enable --now kubelet

    dnf -y --disableexcludes=kubernetes module enable cri-o:$CRIO_VERSION
    dnf -y --disableexcludes=kubernetes install cri-o

    systemctl daemon-reload
    systemctl enable --now crio
}


##################################################### in-between
# should be done in the image, but early images do not have it
# plus, this probably refreshes the latests image so it makes sense at run-time too

function fetch-kube-images() {
    kubeadm config images pull
}
doc-kube fetch-kube-images "retrieve kube core images from dockerhub or similar"


##################################################### run-time

# master only
ADMIN_LOG=$MYDIR/kubeadm-init.log

function create-cluster() {
    cluster-init
    cluster-networking

    copy-kubeconfig-in-user
}
doc-kube create-cluster "start a kube cluster with the current node as a master"


function copy-kubeconfig-in-user() {
    getent passwd $USER >& /dev/null || { echo no such user $USER; return 1; }
    local user_home=$(bash -c "cd ~$(printf %q $USER) && pwd")
    [[ -d $user_home ]] || { echo user $USER has inexistent homedir $user_home; return 1; }
    local group=$(id -g $USER)
    mkdir -p $user_home/.kube
    cp /root/.kube/config $user_home/.kube
    chown -R $USER:$group $user_home/.kube
}


# https://kubernetes.io/docs/tasks/extend-kubernetes/setup-konnectivity/
function create-konnectivity-kubeconfig-and-certs() {
    local server="https://${K8S_API_ENDPOINT_INTERNAL}:6443"
    pushd /etc/kubernetes/pki
    openssl req -subj "/CN=system:konnectivity-server" \
        -new -newkey rsa:2048 -nodes \
        -out konnectivity.csr -keyout konnectivity.key -out konnectivity.csr
    openssl x509 -req -in konnectivity.csr \
        -days 750 -sha256 \
        -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out konnectivity.crt
    kubectl --kubeconfig /etc/kubernetes/konnectivity-server.conf config \
        set-credentials system:konnectivity-server --client-certificate konnectivity.crt --client-key konnectivity.key --embed-certs=true
    kubectl --kubeconfig /etc/kubernetes/konnectivity-server.conf config \
        set-cluster kubernetes --server "$server" --certificate-authority /etc/kubernetes/pki/ca.crt --embed-certs=true
    kubectl --kubeconfig /etc/kubernetes/konnectivity-server.conf config \
        set-context system:konnectivity-server@kubernetes --cluster kubernetes --user system:konnectivity-server
    kubectl --kubeconfig /etc/kubernetes/konnectivity-server.conf config \
        use-context system:konnectivity-server@kubernetes
    rm -f konnectivity.crt konnectivity.key konnectivity.csr
    popd
}

function cluster-init() {

    load-config strict

    swapoff -a

    fetch-kube-images

    systemctl enable --now kubelet

    # the sooner the better
    mkdir -p /etc/kubernetes/pki /etc/kubernetes/konnectivity-server

    local output_dir=$(realpath -m $MYDIR/clusters_/${K8S_CLUSTER_NAME})
    mkdir -p ${output_dir}

    export LOCAL_CERTS_DIR=${output_dir}/pki
    export KUBEADM_TOKEN="$(kubeadm token generate)"

    # we'll need to run this several times
    # as we compute more and more variables
    local kubeadm_config1=/etc/kubernetes/kubeadm-init-config+certsdir.yaml
    local kubeadm_config2=/etc/kubernetes/kubeadm-init-config.yaml

    function generate-etc-configs() {
        (( $BASH_VERSINFO >= 5 )) && shopt -s globstar || {
            echo "Error: globstar unsupported in bash $BASH_VERSINFO - exiting"
            exit 1
        }

        # cleanup any leftover
        git -C $MYDIR clean -f yaml/

        # first populate our templates in-place
        for tmpl in $MYDIR/**/*.in; do
            local b=$(basename $tmpl .in)
            local d=$(dirname $tmpl)
            local o=$d/$b
            echo "Templating $tmpl -> $o"
            envsubst < $tmpl > $o
        done

        # install our config files
        rsync -ai $MYDIR/yaml/*.yaml /etc/kubernetes/
        rsync -ai $MYDIR/yaml/manifests/*.yaml /etc/kubernetes/manifests/
        rsync -ai $MYDIR/yaml/konnectivity-server/*.yaml /etc/kubernetes/konnectivity-server/
        # generate the version without certificatesDir
        # define for future use
        sed '/certificatesDir:/d' $kubeadm_config1 > $kubeadm_config2
    }

    # generate a first time to be able to invoke certificate generation
    generate-etc-configs

    # plain/simple version goes like
    # (1) kubeadm init --pod-network-cidr=10.244.0.0/16
    # (2) cp /etc/kubernetes/admin.conf ~/.kube/config
    # (3) kube-install.sh cluster-networking

    # generate certificates (overwrite ADMIN_LOG)
    kubeadm init phase certs all --config $kubeadm_config1 2>&1 | tee $ADMIN_LOG
    # no longer needed; in fact it would be cool to be allowed to specify
    # --cert-dir on the command line instead of having to create a separate config file
    rm $kubeadm_config1

    # compute cert hash
    export CA_CERT_HASH=$( \
        openssl x509 -pubkey -in ${LOCAL_CERTS_DIR}/ca.crt \
        | openssl rsa -pubin -outform der 2>/dev/null \
        | openssl dgst -sha256 -hex \
        | sed 's/^.* /sha256:/' )

    # the administration client certificate and related stuff
    $MYDIR/generate-admin-client-certs.sh

    # produced by the previous command
    set -a
    CLIENT_CERT_B64=$(base64 -w0  < $LOCAL_CERTS_DIR/kubeadmin.crt)
    CLIENT_KEY_B64=$(base64 -w0  < $LOCAL_CERTS_DIR/kubeadmin.key)
    CA_DATA_B64=$(base64 -w0  < $LOCAL_CERTS_DIR/ca.crt)
    set +a

    # copy certificates in /etc
    rsync -a ${LOCAL_CERTS_DIR}/ /etc/kubernetes/pki/

    function patch-apiserver-manifest() {
        # unfortunately yq script won't seem to accept comments
        # whole point here is to use the contents of
        # add-uds-to-apiserver.yaml
        # (taken verbatim from k8s website's konnectivity howto)
        # and inject it into the manifest as created by kubeadm
        local topatch=/etc/kubernetes/manifests/kube-apiserver.yaml
        # as of 4.25.1, yq now correctly updates the first file
        # https://github.com/mikefarah/yq/issues/1193
        yq eval-all --inplace \
            --from-file $MYDIR/yaml/manifests/add-uds-to-apiserver.yq \
            $topatch $MYDIR/yaml/manifests/add-uds-to-apiserver.yaml
    }

    function inject-konnectivity-manifest() {
        # xxx note that as per
        # https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/
        # the official way to do this would more be to use e.g.
        # /etc/kubelet.d/
        # to store the manifests of statid pods
        # this however requires tweaking of the kubelet options
        # likely in some kubelet service
        # systemctl cat kubelet (which shows 2 instances btw)
        # so let's keep it simple for now
        cp $MYDIR/yaml/manifests/konnectivity-server.yaml \
           /etc/kubernetes/manifests/
    }

    function start-konnectivity-agent() {
        kubectl apply -f /etc/kubernetes/konnectivity-rbac.yaml
        kubectl apply -f /etc/kubernetes/konnectivity-agent.yaml
    }

    # ----------
    # do stuff phase by phase so we can inject konnectivity as a static pod
    function phase() {
        kubeadm init phase "$@" --config $kubeadm_config2 2>&1 | tee -a $ADMIN_LOG
    }
    phase preflight || { echo 'preflight failed - exiting'; exit 1; }
    phase kubeconfig all

    phase kubelet-start
    phase control-plane all

    ### our additions
    patch-apiserver-manifest
    inject-konnectivity-manifest
    create-konnectivity-kubeconfig-and-certs
    ### end

    phase etcd local
    phase upload-config all
    phase upload-certs
    phase mark-control-plane
    phase bootstrap-token
    phase kubelet-finalize all
    phase addon all


    [ -d ~/.kube ] || mkdir ~/.kube
    cp /etc/kubernetes/admin.conf ~/.kube/config
    chown root:root ~/.kube/config

    start-konnectivity-agent
}


# https://github.com/cri-o/cri-o/issues/4276
function -restart-crio-upon-cni-creation() {
    while true; do
        local files=$(ls -l /etc/cni/net.d/* 2> /dev/null)
        if [ -z "$files" ]; then
            echo "EMPTY /etc/cni/net.d - sleeping 4"
            sleep 4
            continue
        fi
        echo "FOUND $files - sleeping 1 before restarting crio"
        sleep 1
        systemctl restart crio
        break
    done
}

function cluster-networking() {

    local flavour=$DEFAULT_NETWORKING
    [[ -n "$CNI_FLAVOUR" ]] && flavour=$CNI_FLAVOUR
    cluster-networking-${flavour}
    -restart-crio-upon-cni-creation
}


# various options for the networking
# flannel -- https://gist.github.com/rkaramandi/44c7cea91501e735ea99e356e9ae7883
# calico  -- https://docs.projectcalico.org/getting-started/kubernetes/quickstart
# weave
function cluster-networking-flannel() {
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
}
function cluster-networking-calico() {
    kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml
    # download for patching
    local calico=yaml/calico-settings.yaml
    curl -o $calico https://projectcalico.docs.tigera.io/manifests/custom-resources.yaml
    yq --inplace '.spec.calicoNetwork.ipPools[0].cidr = "10.244.0.0/16"' $calico
    kubectl create -f $calico
}
# untested yet
function cluster-networking-weave() {
    kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
}


# master only
function setup-kubeproxy() {
    ## the Kube API on localhost:8001 (master only)

    cat >> /etc/systemd/system/kubeproxy8001.service << EOF
[Unit]
Description=kubectl proxy 8001
After=network.target

[Service]
User=root
ExecStart=/bin/bash -c "/usr/bin/kubectl proxy --address=0.0.0.0 --port=8001"
StartLimitInterval=0
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable --now kubeproxy8001
    echo kube proxy running on port:8001
}
doc-kube setup-kubeproxy "create and start a kubeproxy service on port 8001"


function deploy-dashboard() {
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.5.0/aio/deploy/recommended.yaml
}
doc-kube deploy-dashboard "deploy the k8s web UI on master node"


## testing with hello-kubernetes (master only)
function hello-world() {
    cd
    [ -f /etc/fedora-release ] && dnf -y install git
    git clone https://github.com/paulbouwer/hello-kubernetes.git
    cd hello-kubernetes
    cd deploy/helm

    helm install --create-namespace --namespace hello-kubernetes hello-world ./hello-kubernetes

    # get the LoadBalancer ip address.
    kubectl get svc hello-kubernetes-hello-world -n hello-kubernetes -o 'jsonpath={ .status.loadBalancer.ingress[0].ip }'
}
doc-kube hello-world "deploy the hello-world app"

###


# nodes
function join-cluster() {

    echo enabling kubelet
    systemctl enable --now kubelet

    # the crio rpm installs stuff in there !
    [ -d /etc/cni/net.d ] && {
        echo cleaning up CNI
        rm -f /etc/cni/net.d/*
    }

    # use a user@hostname if needed
    local master="$1"
    local fetch="ssh -o StrictHostKeyChecking=accept-new $master kube-install.sh join-command"
    local command=$($fetch)
    if [ -n "$command" ]; then
        echo "Running $command"
        $command
    else
        echo "ERROR: join-cluster:
was not able to find the join command using
$fetch"
        exit 1
    fi
    # take care of the kubectl config file
    [ -d ~/.kube ] || mkdir ~/.kube
    local remoteconfig=$master:.kube/config
    local localconfig=~/.kube/config
    if [ -f ~localconfig ]; then
        localconfig=${localconfig}-$master
    fi
    echo "Fetching $remoteconfig as $localconfig"
    rsync -ai $remoteconfig $localconfig

    -restart-crio-upon-cni-creation

}
doc-kube join-cluster "worker node: join the cluster
example: $0 join-cluster r2lab@sopnode-l1.inria.fr"


# this snap-installed thing is not found when entering through ssh
# unbelievable...
function find-yq() {
    if [ ! -z "$(type -t yq)" ]; then
        return
    elif [ -f /var/lib/snapd/snap/bin/yq ]; then
        PATH=$PATH:/var/lib/snapd/snap/bin
    else
        echo "could not find command yq - exiting"
        exit 1
    fi
}

# on the master, for the nodes
function join-command() {
    if [ ! -f $ADMIN_LOG ]; then
        1>&2 echo "this command is intended to be run on the master node"
        exit 1
    fi
    # e.g.
    # kubeadm join sopnode-w2.inria.fr:6443 \
    # --token hdsdoq.fghmmi8kdstjbfz4 \
    # --discovery-token-ca-cert-hash sha256:<some-hash>
    # in the past we used to look in $ADMIN_LOG
    # but that's no longer possible as we use phases
    # assuming the tokens are all valid forever, so take the first
    # xxx a bit lazy to find the right ca-cert-hash...
    find-yq
    local token=$(kubeadm token list --experimental-output yaml | yq .token | head -1)
    echo kubeadm join $(hostname):6443 --token $token --discovery-token-unsafe-skip-ca-verification
}
doc-kube join-command "master node: display the command for workers to join"


function -undo-cluster() {
    cd $MYDIR
    source configs/$(hostname --short)-config.sh
    local output_dir=$(realpath -m $MYDIR/clusters_/${K8S_CLUSTER_NAME})

    echo "You're going to have to answer 'yes' here"
    echo y | kubeadm reset
    rm -rf ${output_dir}
    rm -rf /etc/kubernetes/*
    rm -rf /etc/cni/net.d
    systemctl stop kubelet
    systemctl disable kubelet

    echo "you might want to also run on your master something like
kubectl drain --ignore-daemonsets $(hostname)
kubectl delete nodes $(hostname)
"
}

function destroy-cluster() {
    -undo-cluster "$@"
}
doc-kube destroy-cluster "undo create-cluster"

function leave-cluster() {
    -undo-cluster "$@"
}
doc-kube leave-cluster "undo join-cluster"



doc-inspect show-rpms "list relevant rpms"
function show-rpms() {
    rpm -qa | egrep 'kube|cri-o|cri-tools'
    dnf module list cri-o
}
doc-inspect clear-rpms "uninstall relevant rpms"
function clear-rpms() {
    rpm -qa | egrep 'kube|cri-o|cri-tools' | xargs rpm -e
}
doc-inspect show-images "list local images"
function show-images() {
    crictl images
}
doc-inspect clear-images "trash unused local images"
function clear-images() {
    crictl rmi --prune
}
doc-inspect show-all "show-rpms + show-images"
function show-all() {
    show-rpms
    show-images
}


doc-inspect version "display git hash for $0"
function version() {
    echo $(git "$@" rev-parse --abbrev-ref HEAD) / $(git -C $MYDIR log HEAD --format=format:%h -1)
}

function pwd() {
    echo $MYDIR
}

for subcommand in "$@"; do
    case "$subcommand" in
        help|--help) help-install; help-kube; help-inspect; exit 1;;
    esac
done
"$@"

# - on a master, do
# [update-os] install prepare create-cluster setup-kubeproxy
# - on a worker, do
# [update-os] install prepare join-cluster
# - knowing that install is actually equivalent to
# install-k8s install-extras install-helm
