# hard-wired yamls

this folder contains sample yaml files for running on the sopnode+r2lab combo

we use the kiada app that ships with book "Kubernetes in action - second edition"

for starters we play with the ability to select nodes for pods

| yaml file | what for |
|-|-|
| `kiada-bare.yaml` | running on any node |
| `kiada-l1.yaml` | choosing a specific sopnode |
| `kiada-fit01.yaml` | choosing a specific R2lab node |
| `kiada-r2lab.yaml` | choosing a (any) R2lab node|
| `kiada-sopnode.yaml` | choosing an infra node (i.e. non R2lab) |

# debug images

the `fedora-with-ping` and `ubuntu-with-ping` folders contain recipes to reuild a little more complete base OS images

```
buildah build -t fedora-with-ping fedora-with-ping
buildah build -t ubuntu-with-ping ubuntu-with-ping
```

# generating node-specific yaml

a convenience script allows to produce a yaml file for a specific combination of node and image; examples

```
create.sh -n fit01
-> run a kiada pod on fit01

create.sh -i ubuntu
-> run a ubuntu-with-ping container on the local hostname

create.sh -s
-> prepare a yaml file for the defaults (kiada + hostname) but stops short of running it

create.sh -n l1                 -> run a kiada pod on sopnode-l1
create.sh -n w3                 -> run a kiada pod on sopnode-w3
create.sh -n fit01 -i fedora    -> run a fedora on fit01
```