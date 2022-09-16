# hard-wired yamls

this folder contains sample yaml files for running on the sopnode+r2lab combo

primarily we use the 'fping' image which is a simple fedora image with a
collection of network tools on board. like ping, among many others

# debug image

the `fping` folder contains a recipe to rebuild a little more complete
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
-> run a fping pod on fit01

testpod.sh -i kiada
-> run a kiada pod on the local hostname

testpod.sh -s
-> prepare a yaml file for the defaults (fping + current hostname) but stops short of running it

testpod.sh -n l1                 -> run a fping pod on sopnode-l1
testpod.sh -n w3                 -> run a fping pod on sopnode-w3
testpod.sh -n fit01 -i fedora    -> run a plain fedora on fit01
```
