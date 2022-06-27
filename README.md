# creating k8s clusters on the sopnode deployment
th
a set of shell utilities to turn a raw fedora box into a k8s cluster

see script `tests/all-in-one.sh` that illustrates how to orchestrate the
deployhment of a complete cluster that crosses the sopnode-faraday NAT thing

## set up

in particular you will need to use

* `rload -i kubernetes` on the nodes that you plan on using

* `join-tunnel` - particularly on FIT nodes because they are not configured to
  do this at boot-time; this will ensure smooth connectivity with the
  `sopnode-*` boxes;

  * note that `test-tunnel` can come in handy, on any of the boxes involved
    (`fit*`, `faraday` and `sopnode-*`) to test for that connectivity

once that connectivity is established, you can build you k8s cluster on top of
it, with

* `kube-install.sh create-cluster` on the master node
* `kube-install.sh networking-calico-postinstall` on the master node as well
  (for some not yet identified reason, this has to be called separately after
  `create cluter`)

* `kube-install.sh join-cluster r2lab@sopnode-l1.inria.fr` for example on a
  worker that wants to join the cluster on `sopnode-l1.inria.fr`

* `fit-label-nodes` to be run on the master after you have added a fit node to
  the cluster; this will add the `r2lab/node=true` label on all R2lab Nodes

## tear down

and optionnally to tear things down cleanly:

* `kube-install.sh destroy-cluster` on the master
* `kube-install.sh leave-cluster` on the workers

## convenience

on all boxes, from an interactive shell, you can type
```bash
ki-utils
```
to add most of this stuff to your shell; example
```bash
[inria_sopnode@faraday ~]$ ssh fit02
Warning: Permanently added 'fit02' (ED25519) to the list of known hosts.
inria_sopnode@fit02's password:

[inria_sopnode@faraday ~]$ ssh root@fit02
Warning: Permanently added 'fit02' (ED25519) to the list of known hosts.
Web console: https://fit02:9090/ or https://192.168.3.2:9090/

Last login: Mon Jun 27 16:21:51 2022 from 192.168.3.100
[root@fit02 ~]# ki-utils
[root@fit02 ~]# test-tunnel
using default id=02
fit02 (192.168.3.2) OK
faraday-pub (138.96.16.97) OK
faraday-priv (192.168.3.100) OK
sopnode-l1-pub (138.96.245.50) OK
sopnode-w1 (138.96.245.51) OK
sopnode-w2 (138.96.245.52) OK
sopnode-w3 (138.96.245.53) OK
[root@fit02 ~]# exit
logout
Connection to fit02 closed.
```

also you can do stuff like (`ki = kube-instal.sh` is defined by `ki-utils`)
```bash
ki self-update   # to pull the latest version from github
ki version       # to display the current version (the git hash)
```

# notes on IPPools

currently we use 2 separate IP Pools for the sopnode and the FIT* areas; this is actually not strictly necessary I believe.
