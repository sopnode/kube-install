# using fedora's kubernetes rpms

some notes about an experiment done in July 2022 to use the fedora-native rpms

which turned out to be badly broken...


```
# note that kubelet comes with rpm kubernetes-node
# and kubectl comes with kubernetes-client
# which are pulled by kubernetes
dnf install -y kubernetes

dnf module enable -y cri-o:1.24
dnf install -y cri-o cri-tools

systemctl enable --now crio

dnf install -y kubernetes-kubeadm

dnf clean all

kube-install.sh prepare
```

actually looks rather promising...

## status

* kubelet refuses to start, due to some misconfig
* kubeadm has dumped a drop-in config in `/etc/systemd/system/kubelet.service.d/kubeadm.conf` that `kubelet` does not like
* I have commented them both out
  ```
  Jun 28 11:20:54 fit06 kubelet[170771]: Flag --fail-swap-on has been deprecated, This parameter should be set via the config file specified by the Kubelet's ->
  Jun 28 11:20:54 fit06 kubelet[170771]: Flag --pod-manifest-path has been deprecated, This parameter should be set via the config file specified by the Kubele>
  ```
  still kubelet does not take off
* remains an issue with `--network-plugin` and `--cni-conf-dir`

```
[root@fit06 ~]# ki join-cluster r2lab@sopnode-w2.inria.fr
enabling kubelet
Created symlink /etc/systemd/system/multi-user.target.wants/kubelet.service → /usr/lib/systemd/system/kubelet.service.
Running kubeadm join sopnode-w2.inria.fr:6443 --token gxwvxp.hq0fwfngi0w5skt7 --discovery-token-unsafe-skip-ca-verification
[preflight] Running pre-flight checks
	[WARNING SystemVerification]: missing optional cgroups: blkio
[preflight] Reading configuration from the cluster...
[preflight] FYI: You can look at this config file with 'kubectl -n kube-system get cm kubeadm-config -o yaml'
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Starting the kubelet
[kubelet-start] Waiting for the kubelet to perform the TLS Bootstrap...
```

but then kubelet is complaining

```
journalctl ...
Jun 28 11:20:54 fit06 systemd[1]: kubelet.service: Scheduled restart job, restart counter is at 3.
Jun 28 11:20:54 fit06 systemd[1]: Stopped kubelet.service - Kubernetes Kubelet Server.
Jun 28 11:20:54 fit06 systemd[1]: Started kubelet.service - Kubernetes Kubelet Server.
Jun 28 11:20:54 fit06 kubelet[170771]: Error: failed to parse kubelet flag: unknown flag: --network-plugin
Jun 28 11:20:54 fit06 kubelet[170771]: Usage:
Jun 28 11:20:54 fit06 kubelet[170771]:   kubelet [flags]
```

found reference to these 2 outdated options in file `/etc/systemd/system/kubelet.service.d/kubeadm.conf`
which comes with rpm `kubernetes-kubeadm`

page to see was https://kubernetes.io/docs/tasks/administer-cluster/kubelet-config-file/


###
continuing on sopnode-w3

kubelet not starting properly

some flags present in the config file(s) were obsoleted

```
OK --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf
OK --kubeconfig=/etc/kubernetes/kubelet.conf
DEP --fail-swap-on=false
DEP --pod-manifest-path=/etc/kubernetes/manifests
NO --network-plugin=cni 
NO --cni-conf-dir=/etc/cni/net.d 
NO --cni-bin-dir=/usr/libexec/cni
DEP --cluster-dns=10.96.0.10 
DEP --cluster-domain=cluster.local
DEP --authorization-mode=Webhook 
DEP --client-ca-file=/etc/kubernetes/pki/ca.crt
DEP --cgroup-driver=systemd

DEP --container-runtime=remote
OK --container-runtime-endpoint=unix:///var/run/crio/crio.sock
DEP --pod-infra-container-image=k8s.gcr.io/pause:3.7
```

so, tweaked `/etc/systemd/system/kubelet.service.d/kubeadm.conf` to read

```
[Service]
#Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf --fail-swap-on=false"
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
#Environment="KUBELET_SYSTEM_PODS_ARGS=--pod-manifest-path=/etc/kubernetes/manifests"
Environment="KUBELET_SYSTEM_PODS_ARGS="
#Environment="KUBELET_NETWORK_ARGS=--network-plugin=cni --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/usr/libexec/cni"
Environment="KUBELET_NETWORK_ARGS="
#Environment="KUBELET_DNS_ARGS=--cluster-dns=10.96.0.10 --cluster-domain=cluster.local"
Environment="KUBELET_DNS_ARGS="
#Environment="KUBELET_AUTHZ_ARGS=--authorization-mode=Webhook --client-ca-file=/etc/kubernetes/pki/ca.crt"
Environment="KUBELET_AUTHZ_ARGS="
#Environment="KUBELET_EXTRA_ARGS=--cgroup-driver=systemd"
Environment="KUBELET_EXTRA_ARGS="

# This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
#EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
Environment="KUBELET_KUBEADM_ARGS=--container-runtime-endpoint=unix:///var/run/crio/crio.sock"

ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_SYSTEM_PODS_ARGS $KUBELET_NETWORK_ARGS $KUBELET_DNS_ARGS $KUBELET_AUTHZ_ARGS $KUBELET_EXTRA_ARGS $KUBELET_KUBEADM_ARGS

Restart=always
StartLimitInterval=0
RestartSec=10
```

a little better, but not quite there yet...
