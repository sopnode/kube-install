# creating k8s clusters on the sopnode deployment

this is a set of shell utilities to turn a raw fedora box into a k8s cluster

see script `tests/all-in-one.sh` that illustrates how to orchestrate the
deployment of a complete cluster that crosses the sopnode-faraday NAT barrier

*note* this version has support for fedora 37 only

## set up

in particular you will need to use

* `rload -i kubernetes` on the nodes that you plan on using

* `join-tunnel` - particularly on FIT nodes because they are not configured to
  do this at boot-time; this will ensure smooth connectivity with the
  `sopnode-*` boxes;
  *note*: it turns out that runnin this command on the FIT
  nodes is not that crucial, and everything will work just fine unless you need
  to send packets to any end of the IP/IP tunnel between sopnode and R2lab.

  * note that `test-tunnel` can come in handy, on any of the boxes involved
    (`fit*`, `faraday` and `sopnode-*`) to test for that connectivity

once that connectivity is established, you can build you k8s cluster on top of
it, with

* `kube-install.sh create-cluster` on the master node

* `kube-install.sh join-cluster r2lab@sopnode-l1.inria.fr` for example on a
  worker that wants to join the cluster on `sopnode-l1.inria.fr`

* `kube-install.sh enable-multus` is an optional step

## tear down

and optionnally to tear things down cleanly:

* `kube-install.sh destroy-cluster` on the master
* `kube-install.sh leave-cluster` on the workers

## installation

most users do not need to worry about installing, as the `kubernetes` r2lab
image has everything in place already, as well as the sopnode wired boxes;
however if needed, you can use the following commands to make a fresh fedora
installation compatible with the system

* `kube-install.sh prepare` : for tweaking linux globally (swap, sysctls, etc..)
* `kube-install.sh install` : for installing the required k8s packages

## convenience

**UPDATE** it is no longer needed to explicitly type `ki-utils` on either side
(servers or nodes)of the sopnode deployment

the package comes with a few convenience commands; examples
```bash
[inria_sopnode@faraday ~]$ ssh root@fit02
Warning: Permanently added 'fit02' (ED25519) to the list of known hosts.
Web console: https://fit02:9090/ or https://192.168.3.2:9090/

Last login: Mon Jun 27 16:21:51 2022 from 192.168.3.100
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
ki self-update    # to pull the latest version from github
ki version        # to display the current version (the git hash)
ki pwd            # to display the location where the tool is installed
cdki              # to cd in this location
```

## implementation notes

* because the sopnode boxes are not administered like the FIT boxes, the
  location of the various tools can be a little awkward at times; for one thing,
  the git repo is cloned on each participating machine, and as of now, it is located
  * in `/root/kube-install` on the FIT nodes
  * in `/usr/share/kube-install` on the sopnode boxes

  this is because `/root/` is not readable by non-root users
