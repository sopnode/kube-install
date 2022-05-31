---
jupytext:
  formats: md:myst
  text_representation:
    extension: .md
    format_name: myst
    format_version: 0.13
    jupytext_version: 1.13.8
kernelspec:
  display_name: Python 3 (ipykernel)
  language: python
  name: python3
---

# test results

+++

## test setup

we setup a k8s cluster with

* one wired master (typically sopnode-w2)
* one wired worker (typically sopnode-w3)
* one wireless worker in R2lab (typically fit01)

on each of these workers we launch a testpod based on a simple fedora image (see `kiada/fedora-with-ping/Dockerfile`) with the basic networking tools (ping, host, nc, etc..)

+++

## what is tested ?

+++

Most tests are about running simple network tools **from inside a user pod**  
there are 2 kinds of tests:

* A. the ones that target the outside of the cluster
* B. the ones that target the inside of the cluster

and namely:

* A. `check-dns` will check if names can be resolved from the pod; the names to resolve are `kubernetes` `r2lab.inria.fr` and `github.com`
* A. `check-http` will check for outside connectivity, by opening a tcp connection to some outside hosts; this targets `r2lab.inria.fr` `github.com` and `140.82.121.4` so obviously, if check-dns fails, we can get a maximum of 2/3 on this one
* B. `check-ping` will run ping inside the testpod targetting the IP of all the other testpods (including itself); 
* B. `check-log` will run **inside the host** a call to `kubelet logs` for all testpods
* B. `check-exec` will run **inside the host** a call to `kubelet exec` for all testpods

+++

## how is it presented ?

we show:

* the A results in 2 diagrams; on the left hand side is when the test runs on the wired side, and on the right hand side the tests that run on the wireless side

* the B results are shown in 4 diagrams:
  * on the top row we have the tests that run on the wired side, so obviously the bottom is for tests that run on the wireless side
  * the left hand side is for tests that target the wired side, and the right had side is for tests that target the

+++

## the results

```{code-cell} ipython3
import postprocess
```

```{code-cell} ipython3
df1, df2, *_ = postprocess.load("SUMMARY-05-27-13-48-27.csv")
postprocess.show_all(df1, df2)
```

```{code-cell} ipython3
df1, df2, *_ = postprocess.load("SUMMARY-05-30-16-05-53-outgoingnat=false.csv")
postprocess.show_all(df1, df2)
```

```{code-cell} ipython3
latest = postprocess.latest_csv()
print(f"{latest=}")

df1, df2, *_ = postprocess.load(latest)
postprocess.show_all(df1, df2)
```

```{code-cell} ipython3
# for instance, extracting the 'check-http' bar from the upper-left diagram
# would mean to do
extract = df1[df1['wired-from'] & (df1['test']=='check-http')]
# how many entries
extract.shape[0]
```

```{code-cell} ipython3
# for instance, extracting the 'check-http' bar from the upper-left diagram
# would mean to do
extract = df2[~df2['wired-from'] & ~df2['wired-to'] & (df2['test']=='check-ping')]
# how many entries
extract.shape[0]
```

****
