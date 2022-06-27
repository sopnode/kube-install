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

* `fit-label-nodes` to be run on the master after you have added a fit node to the cluster; this will add the `r2lab/node=true` label on all R2lab Nodes

## tear down

and optionnally to tear things down cleanly:

* `kube-install.sh destroy-cluster` on the master
* `kube-install.sh leave-cluster` on the workers
