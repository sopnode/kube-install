# upgrading sopnode-*

## starting point

fedora-35 with kube-install circa origin/f35

## system upgrade

* using Francis's upgrade procedure

  as documented in (vpn required) <https://doc-si.inria.fr/display/SU/Demander+l%27installation+de+mon+systeme#tab-Sophia>

  which  boils down to

  ```bash
  srv-diana $
  RELEASEVER=36
  HOST=root@sopnode-w2.inria.fr
  rsync -a --exclude BUILD /net/servers/fedora/$RELEASEVER/ $HOST:/var/tmp/ff
  ```

  and

  ```
  sopnode-w2 #
  cd /var/tmp/ff
  make upgrade mailto=thierry.parmentelat@inria.fr package=minimal
  ```

## adjustments

```
sopnode-w2 #
ki install
# visual check
# the cri-tools rpm in f36 is 1.22 and that seems OK
ki show-rpms
```
