# rebuilding the kubernetes images on fedora-36

## prelude

starting from image `fedora-36-by-os-upgrade`

```
dnf -y update
dnf clean all

# might make sense to rsave this one as e.g. fedora-36-2002-07

git -C /root/r2lab-embedded pull
cd /root
git clone https://github.com/parmentelat/kube-install.git

# make sure to switch onto the proper branch - probably devel
cd kube-install
git switch devel

cd /usr/bin
ln -s /root/kube-install/kube-install.sh
cd /root/
mkdir .ssh
cd .ssh
# add r2lab key in ~/.ssh (copy id_rsa and id_rsa.pub from another f35 node)
OLDER=fit01
rsync $OLDER:.ssh/id_rsa .
rsync $OLDER:.ssh/id_rsa.pub .
rm ~/.ssh/known_hosts*

```

## installing

```
# clear-* are just in case...
# kube-install.sh clear-rpms
# kube-install.sh clear-images

# this is not done as part of the prepare step
# as it does not apply to the wired servers
kube-install.sh prepare-firewall
kube-install.sh prepare
kube-install.sh install
kube-install.sh show-rpms
kube-install.sh show-images
dnf clean all
```

## postinstall
```
kube-install.sh install-yq # may be useless...

# just in case
kube-install.sh leave-cluster
```

checkpoint that image

```
NODE=1
rsave -o fedora-36-ki-0.14 $NODE
```

## images

at this point `crictl` has no image on board; trying to run `kube-install.sh
fetch-kube-images` won't work (cannot reach a master, etc..)

plus, it is unclear that it would not pull unnecessary images

so what I did for the `kube-f36-ki-0.14-images` image was to simply test

```
crictl rmi --prune
kube-install.sh join-cluster r2lab@sopnode-w2.inria.fr

# WAIT until all the images have been pulled
# should have 6 images
# ---
crictl images
# docker.io/calico/cni
# docker.io/calico/node
# docker.io/calico/pod2daemon-flexvol
# k8s.gcr.io/kube-proxy
# registry.k8s.io/pause
# us.gcr.io/k8s-artifacts-prod/kas-network-proxy/proxy-agent
# ---

# don't forget to leave-cluster once all is up and running
kube-install.sh leave-cluster

# if relevant, build the uping image for kube-install's tests
# build testpod image
cd $(kube-install.sh pwd)
cd testpod
./build.sh

crictl images
# now there should be 7 images, with the addition of
# localhost/fedora-with-ping
```

and then

```
rsave -o fedora-36-ki-0.14-images $NODE
```

## trying the standard fedora repo

this failed miserably in f36, with a lot of wasted time, so...

see [f36-plain-fedora-rpms] for more details
