# ---
# jupyter:
#   jupytext:
#     cell_metadata_filter: all,-hidden,-heading_collapsed,-run_control,-trusted
#     notebook_metadata_filter: all, -jupytext.text_representation.jupytext_version,
#       -jupytext.text_representation.format_version, -language_info.version, -language_info.codemirror_mode.version,
#       -language_info.codemirror_mode, -language_info.file_extension, -language_info.mimetype,
#       -toc
#     text_representation:
#       extension: .py
#       format_name: percent
#   kernelspec:
#     display_name: Python 3 (ipykernel)
#     language: python
#     name: python3
#   language_info:
#     name: python
#     nbconvert_exporter: python
#     pygments_lexer: ipython3
# ---

# %% [markdown]
# # test results

# %% [markdown]
# ## test setup
#
# we setup a k8s cluster with
#
# * one wired master (typically sopnode-w2)
# * one wired worker (typically sopnode-w3)
# * one wireless worker in R2lab (typically fit01)
#
# on each of these workers we launch a testpod based on a simple fedora image (see `kiada/fedora-with-ping/Dockerfile`) with the basic networking tools (ping, host, nc, etc..)

# %% [markdown]
# ## what is tested ?

# %% [markdown]
# Most tests are about running simple network tools **from inside a user pod**  
# there are 2 kinds of tests:
#
# * A. the ones that target the outside of the cluster
# * B. the ones that target the inside of the cluster
#
# and namely:
#
# * A. `check-api` checks the ability that a pod has to join the kubernetes API on 10.96.0.1
# * A. `check-dns` will check if names can be resolved **from the testpod**; the names to resolve are `kubernetes` `r2lab.inria.fr` and `github.com`
# * A. `check-http` will check for outside connectivity **from a testpod**, by opening a tcp connection to some outside hosts; this targets `r2lab.inria.fr` `github.com` and `140.82.121.4` so obviously, if check-dns fails, we can get a maximum of 2/3 on this one
#
# *** 
#
# * B. `check-ping` will run ping **inside the testpod** targetting the IP of all the other testpods (including itself); 
# * B. `check-log` will run **inside the host** a call to `kubelet logs` for all testpods
# * B. `check-exec` will run **inside the host** a call to `kubelet exec` for all testpods

# %% [markdown]
# ## notes on those tests

# %% [markdown]
# * apparently the DNS IP endpoint on `10.96.0.10` is configured to NOT answer
#   ICMP; if tested on the wired side only, a ping to `10.96.0.10` from the
#   testpod will fail, BUT that IP address does solve hostnames when doing e.g.
#   `host github.com 10.96.0.10`
# * same for the `10.96.0.1`; that is why `check-api` checks for that properly
#   using curl
# * note that `check-http` has 3 destinations, 2 of which are fqdn's; so when
#   `check-dns` fails, the best that `check-http` can achieve is 1/3

# %% [markdown]
# ## how is it presented ?
#
# we show:
#
# * the A results in 2 diagrams; on the left hand side is when the test runs on the wired side, and on the right hand side the tests that run on the wireless side
#
# * the B results are shown in 4 diagrams:
#   * here again the tests that **originate on the wired** side are shown on the **left hand side**; so obviously the right hand side is for tests that run on the wireless side
#   * on the **top row** we have the tests that run **towards the wired side**, so obviously the bottom is for tests that run towards the wireless side

# %%
import matplotlib.pyplot as plt

# %matplotlib notebook

# %%
# figures size
from IPython.core.pylabtools import figsize
figsize(10, 12)

# %%
import postprocess

# %% [markdown]
# ## past results

# %%
#df1, df2, *_ = postprocess.load("SUMMARY-06-28-16-20-29.csv")
#postprocess.show_all(df1, df2)

# %% [markdown]
# ## latest results

# %%
latest = postprocess.latest_csv()
df1, df2, *_ = postprocess.load(latest)

print(f"{latest=}, {df1.shape=} {df2.shape=}")
postprocess.show_all(df1, df2)

# %% [markdown]
# ## digging...

# %%
# for example:

# the upper right 'check-api' bar
extract1 = df1[(~df1['wired-from']) & (df1['test']=='check-api')]

# how many entries
print(f"{extract1.shape[0]=}")

extract1.head()

# %%
# df2 is a little different

extract2 = df2[(df2['from'] == 'fping-w2-pod') & (df2['to'] == 'fping-w3-pod')]
extract2

# %% [markdown]
# ****
