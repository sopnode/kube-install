########## pseudo docstrings
MYDIR=$(dirname $(readlink -f $BASH_SOURCE))

# for the mac where readlink has no -f option
[ -z "$MYDIR" ] && MYDIR=$(dirname $BASH_SOURCE)
[ -z "$_sourced_r2labutils" ] && source ${MYDIR}/r2labutils.sh

cd $MYDIR

create-doc-category install "commands to make the node ready"
create-doc-category kube "commands to manage the kube cluster"

function emergency-exit() {
    echo EMERGENCY; exit 1
}

function breakpoint() {
    echo -n "BREAKPOINT - type Enter when done ... "
    read _
}

##################################################### imaging

## references

### fedora

# our version: f35
# https://kubernetes.io/docs/setup/production-environment/container-runtimes/#cri-o
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

# still needed afterwards is tweaking your firewall

### ubuntu - no longer supported

# our version: 21.04
# https://www.techrepublic.com/article/how-to-install-kubernetes-on-ubuntu-server-without-docker/

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
    # NOTE 1: ubuntu
    # this has not been extensively tested on ubuntu
    # in addition, on ubuntu still, it seems there is a need to do also
    # ufw disable
    # # xxx probably needs to be mode more permanent
    # NOTE 2: trying to mask services marked as swap looked promising
    # but not quite right
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
    [ -f /etc/fedora-release ] && fedora-install-k8s
    [ -f /etc/lsb-release ]    && ubuntu-install-k8s
    fetch-kube-images
}
doc-install install "install kubernets core"


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

    dnf -y install kubelet kubeadm kubectl --disableexcludes=kubernetes

    systemctl enable --now kubelet

    # find proper cri-o version (closest to your installed kube's)

    # defines VERSION_ID
    source /etc/os-release

    KVERSION=$(rpm -q kubectl | sed -e s/kubectl-// | cut -d. -f1,2)
    echo found kubectl version as $KVERSION
    dnf module list cri-o
    case $VERSION_ID in
        34) CVERSION=1.21;;
        35) CVERSION=1.22;;
        *) echo WARNING: you should define CVERSION for fedora $VERSION_ID; CVERSION=$KVERSION;;
    esac
    echo using cri-o CVERSION=$CVERSION

    dnf -y --disableexcludes=kubernetes module enable cri-o:$CVERSION
    dnf -y --disableexcludes=kubernetes install cri-o

    systemctl daemon-reload
    systemctl enable --now crio
}


function ubuntu-install-k8s() {
    apt update && apt -y upgrade
    apt -y install containerd
    mkdir -p /etc/containerd/ ; containerd config default > /etc/containerd/config.toml

    apt -y install apt-transport-https
    curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
    apt update && apt -y install kubelet kubeadm kubectl
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
# the *`kubeadm init ..`* command issues a *`kubeadm join`* command that must be copied/pasted ...
ADMIN_LOG=$MYDIR/kubeadm-init.log

function create-cluster() {
    cluster-init
    cluster-networking

    echo "========== to join this cluster (see $ADMIN_LOG)"
    tail -2 $ADMIN_LOG
    echo "=========="
}
doc-kube create-cluster "start a kube cluster with the current node as a master"


# https://kubernetes.io/docs/tasks/extend-kubernetes/setup-konnectivity/
function create-konnectivity-kubeconfig-and-certs() {
    pushd /etc/kubernetes/pki
    openssl req -subj "/CN=system:konnectivity-server" \
        -new -newkey rsa:2048 -nodes \
        -out konnectivity.csr -keyout konnectivity.key -out konnectivity.csr
    openssl x509 -req -in konnectivity.csr \
        -days 750 -sha256 \
        -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out konnectivity.crt
    SERVER=$(kubectl config view -o jsonpath='{.clusters..server}')
    kubectl --kubeconfig /etc/kubernetes/konnectivity-server.conf config \
        set-credentials system:konnectivity-server --client-certificate konnectivity.crt --client-key konnectivity.key --embed-certs=true
    kubectl --kubeconfig /etc/kubernetes/konnectivity-server.conf config \
        set-cluster kubernetes --server "$SERVER" --certificate-authority /etc/kubernetes/pki/ca.crt --embed-certs=true
    kubectl --kubeconfig /etc/kubernetes/konnectivity-server.conf config \
        set-context system:konnectivity-server@kubernetes --cluster kubernetes --user system:konnectivity-server
    kubectl --kubeconfig /etc/kubernetes/konnectivity-server.conf config \
        use-context system:konnectivity-server@kubernetes
    rm -f konnectivity.crt konnectivity.key konnectivity.csr
    popd
}


function cluster-init() {

    # tmp xxx reinstate when not in devel mode
    #fetch-kube-images

    swapoff -a

    # spot the config file for that host
    local localconfig="$MYDIR/configs/$(hostname --short)-config.sh"

    if [ ! "$localconfig" ]; then
        echo "local config file $localconfig not found - aborting"
        exit 1
    fi

    # set -a / set +a is for exporting the variables
    set -a; source $localconfig; set +a

    local output_dir=$(realpath -m $MYDIR/clusters_/${K8S_CLUSTER_NAME})
    mkdir -p ${output_dir}

    export LOCAL_CERTS_DIR=${output_dir}/pki
    export KUBEADM_TOKEN="$(kubeadm token generate)"

    # we'll need to run this several times
    # as we compute more and more variables
    local kubeadm_config1=/etc/kubernetes/kubeadm-init-config+certsdir.yaml
    local kubeadm_config2=/etc/kubernetes/kubeadm-init-config.yaml

    function generate_etc_configs() {
        # install our config files
        rsync -ai $MYDIR/yaml/*.yaml /etc/kubernetes
        # and these need to go through variable substitution w/ envsubst
        local tmpl
        for tmpl in $MYDIR/yaml/*.yaml.in; do
            local b=$(basename $tmpl .in)
            # echo "refreshing /etc/kubernetes/$b"
            envsubst < $tmpl > /etc/kubernetes/$b
        done
        # generate the version without certificatesDir
        # define for future use
        sed '/certificatesDir:/d' $kubeadm_config1 > $kubeadm_config2
    }

    # generate a first time to be able to invoke certificate generation
    generate_etc_configs

    # generate certificates (overwrite ADMIN_LOG)
    kubeadm init phase certs all --config $kubeadm_config1 2>&1 | tee $ADMIN_LOG

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
        # xxx would be nice to automatically inject the contents of
        # yaml/manifests/apiserver-uds.yaml
        # into what kubeadm init has created in
        # /etc/kubernetes/manifests/kube-apiserver.yaml
        # NOTE: this is not just a simple dictionary merge
        # because in the apiserver containers key there
        # actually is a list... 
        # for now this has been done manually
        cp $MYDIR/yaml/manifests/kube-apiserver+uds.yaml \
           /etc/kubernetes/manifests/kube-apiserver.yaml
    }

    function inject-konnectivity-manifest() {
        cp $MYDIR/yaml/manifests/konnectivity-server.yaml \
           /etc/kubernetes/manifests/
    }

    # ----------
    # do stuff phase by phase so we can inject konnectivity as a static pod
    function phase() {
        kubeadm init phase "$@" --config $kubeadm_config2 2>&1 | tee -a $ADMIN_LOG
    }
    phase preflight
    phase kubeconfig all
    phase kubelet-start
    phase control-plane all

    patch-apiserver-manifest
    inject-konnectivity-manifest
    create-konnectivity-kubeconfig-and-certs

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
}


function cluster-networking() {
    cluster-networking-flannel
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
    # unfinished - see web page mentioned above
}
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
    local master="$1"
    local fetch="ssh $master kube-install/kube-install.sh show-join"
    local command=$($fetch)
    # somehow the backslash stands in the way
    command=$(sed -e 's/\\//' <<< $command)
    if [ -n "$command" ]; then
        echo "Running $command"
        $command
    else
        echo "ERROR: join-cluster:
was not able to find the join command using
$fetch"
        exit 1
    fi
}
doc-kube join-cluster "worker node: join the cluster (master hostname as 1st arg)"


# on the master, for the nodes
function show-join() {
    # xxx could be a little more paranoid
    # and check the token is still valid
    if [ -f $ADMIN_LOG ]; then
        tail -2 $ADMIN_LOG
    else
        1>&2 echo "this command is intended to be run on the master node"
        exit 1
    fi
}
doc-kube show-join "master node: display the command for the workers to join"


function kube-teardown() {
    cd $MYDIR
    source configs/$(hostname --short)-config.sh
    local output_dir=$(realpath -m $MYDIR/clusters_/${K8S_CLUSTER_NAME})

    echo "You're going to have to answer 'yes' here"
    kubeadm reset
    rm -rf ${output_dir}
    rm -rf /etc/kubernetes/*
    echo "you might want to also run on your master something like
kubectl drain --ignore-daemonsets $(hostname)
kubectl delete nodes $(hostname)
"
}
doc-kube kube-teardown "undo create-cluster or kubeadm join - use with care..."



for subcommand in "$@"; do
    case "$subcommand" in
        help|--help) help-install; help-kube; exit 1;;
    esac
done
"$@"

# - on a master, do
# [update-os] install prepare create-cluster setup-kubeproxy
# - on a worker, do
# [update-os] install prepare join-cluster
# - knowing that install is actually equivalent to
# install-k8s install-extras install-helm
