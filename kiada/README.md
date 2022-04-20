this folder contains sample yaml files for running on the sopnode+r2lab combo

we use the kiada app that ships with book "Kubernetes in action - second edition"

for starters we play with the ability to select nodes for pods

| yaml file | what for |
|-|-|
| `kiada-bare.yaml` | running on any node |
| `kiada-fit01.yaml` | choosing a specific R2lab node |
| `kiada-r2lab.yaml` | choosing a (any) R2lab node|
| `kiada-sopnode.yaml` | choosing an infra node (i.e. non R2lab) |
