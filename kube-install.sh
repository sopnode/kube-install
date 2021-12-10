## references

### fedora

# our version: f34
# https://kubernetes.io/docs/setup/production-environment/container-runtimes/#cri-o
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

### ubuntu

# our version: 21.04
# https://www.techrepublic.com/article/how-to-install-kubernetes-on-ubuntu-server-without-docker/

####
# how to push this initially
# for n in vnode0{0,1,2}; do rsync -rltpi kube-install.sh $(plr $n):; done

# TODO
#
# * explore setting $KUBECONFIG as per
# https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/

# silence apt install, esp. painful about kernel upgrades, that won't reboot on their own
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
    touch touch /etc/systemd/zram-generator.conf
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

function update-os() {
    [ -f /etc/fedora-release ] && dnf -y update
    [ -f /etc/lsb-release ]    && apt -y update
}

function install() {
    install-k8s
    install-extras
    install-helm
}

# all nodes
function install-extras() {
    [ -f /etc/fedora-release ] && dnf -y install git openssl netcat jq buildah
    [ -f /etc/lsb-release ]    && apt -y install git openssl netcat # jq
}


# all nodes
function install-k8s() {
    [ -f /etc/fedora-release ] && fedora-install-k8s
    [ -f /etc/lsb-release ]    && ubuntu-install-k8s
}


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


# master only
# the *`kubeadm init ..`* command issues a *`kubeadm join`* command that must be copied/pasted ...
ADMIN_LOG=~/kubeadm-init.log

function create-cluster() {
    cluster-init
    cluster-networking

    echo "========== to join this cluster (see $ADMIN_LOG)"
    tail -2 $ADMIN_LOG
    echo "=========="
}

function cluster-init() {
    hostnamectl set-hostname kube-master
    kubeadm config images pull
    # xxx I don't get how this comes back into force, but...
    swapoff -a
    kubeadm init --pod-network-cidr=10.244.0.0/16 > $ADMIN_LOG 2>&1

    mkdir ~/.kube
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


# nodes
function join-cluster() {
    echo "join-cluster: YOU NEED TO COPY-PASTE for now"
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


# all nodes
function install-helm() {
    cd
    [ -f /etc/fedora-release ] && dnf -y install openssl
    curl -fsSL -o install-helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    bash install-helm.sh
    helm version
}


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


for subcommand in "$@"; do
    $subcommand
done

# - on a master, do
# [update-os] install prepare create-cluster setup-kubeproxy
# - on a worker, do
# [update-os] install prepare join-cluster
# - knowing that install is actually equivalent to
# install-k8s install-extras install-helm
