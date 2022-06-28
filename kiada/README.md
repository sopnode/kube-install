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

note that the 2 last ones require the use of the `fit-label-nodes` command so
that one can differentiate between the 2 sides.

# debug images

the `fedora-with-ping` folder contain a recipe to rebuild a little more complete
base OS image, with network-oriented tools for troubleshooting

to build locally:

```
./build.sh
```

# generating node-specific yaml

a convenience script allows to produce a yaml file for a specific combination of
node and image; examples

```
testpod.sh -n fit01
-> run a kiada pod on fit01

testpod.sh -i fping
-> run a fedora-with-ping container on the local hostname

testpod.sh -s
-> prepare a yaml file for the defaults (kiada + hostname) but stops short of running it

testpod.sh -n l1                 -> run a kiada pod on sopnode-l1
testpod.sh -n w3                 -> run a kiada pod on sopnode-w3
testpod.sh -n fit01 -i fedora    -> run a fedora on fit01
```
