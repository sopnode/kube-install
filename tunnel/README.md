# miscell attempts

## `vxlan.sh`

is an attempt at creating a simple vxlan between 2 fit nodes

### status

assuming N1=1 and N2=2

* testing means doing from node1
  ```bash
  fit01# ping 10.0.0.2
  ```
* what we observe in this scenario is
  * an ARP request `who-has 10.0.0.2, tell fit01` on `node1`'s `vxlan` interface
  * same request is seen on `node1`'s `control` interface
  * it goes on the wire, and it seen on `node2`'s `control` interface
  * **BUT** it does not make it to `node2`'s `vxlan` interface
  * and so no ARP reply can be seen from any of those 4 vantage points

### troubleshooting

* the `iptables` are completely clear
* the kernel's `forwarding` mode is on
* setting `rp_filter` to 0 does not solve it
* creating the `vxlan` interface with the `proxy` setting did not help either
  (it even feels like it made matters worse)

food for thought maybe: it's funny that we're seeing something that is again
very close to the k8s symptom, i.e. some traffic that comes on a physical
interface and that we expect to see flowing on a secondary interface, but that
does not:

* in the present case there's no netns nor and no, the secondary interface is directly the vxlan
* in the k8s case, the secondary interface was the veth interface associated with the receiving pod

