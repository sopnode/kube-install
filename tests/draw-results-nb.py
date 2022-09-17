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
# on each of these workers we launch a testpod based on a simple fedora image
# (see `tests/testpod/fping/Dockerfile`) with the basic networking tools (ping, host, nc, etc..)

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
# * A. `check-api` checks the ability **for a testpod** to join the kubernetes API on 10.96.0.1
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
#   using `curl`
# * note that `check-http` has 3 destinations, 2 of which are fqdn's; so when
#   `check-dns` fails, the best that `check-http` can achieve is 1/3

# %% [markdown]
# ## how is it presented ?
#
# we show:
#
# * the A results in 2 diagrams (first line of diagrams)
#   * on the **left hand side** is when the test **runs on the wired side**,
#   * and on the **right hand side** the tests that **run on the wireless side**
#
# * the B results are shown in 4 diagrams (lines 2 and 3 of diagrams)
#   * here again the tests that **originate on the wired** side are shown on the **left hand side**; so obviously the right hand side is for tests that run on the wireless side
#   * on the **top row** we have the tests that run **towards the wired side**, so obviously the bottom is for tests that run towards the wireless side

# %%
import matplotlib.pyplot as plt
import pandas as pd

# %matplotlib notebook

# %%
# figures size
from IPython.core.pylabtools import figsize
figsize(10, 10)

# %%
import postprocess

# %% [markdown]
# ## past results

# %%
#df1, df2 = postprocess.show_file("SUMMARY-prod-08-25-13-22-42.csv")

# %% [markdown]
# ## latest results

# %%
latest = postprocess.latest_csv()
print(f"{latest=}")
df1, df2 = postprocess.show_file(latest)

# %% [markdown]
# ## zooming in

# %% [markdown]
# ### summary from df1

# %%
# http individually
all_https = df1[df1.test == 'check-http']
https = all_https.rename(columns={'success': 'http'}).pivot_table('http', columns='from')


# %%
# dns individually
all_dnss = df1[df1.test == 'check-dns']
dnss = all_dnss.rename(columns={'success': 'dns'}).pivot_table('dns', columns='from')


# %%
pd.concat([https, dnss])

# %% [markdown]
# ### execs

# %% [markdown]
# a cross-table to see all the individual execs (all node pairs)

# %%
pings = df2[df2.test == 'check-exec']
pings.pivot_table('success', index='from', columns='to')

# %% [markdown]
# ### pings

# %% [markdown]
# a cross-table to see all the individual pings (all node pairs)

# %%
pings = df2[df2.test == 'check-ping']
pings.pivot_table('success', index='from', columns='to')

# %% [markdown]
# ## digging...

# %% [markdown]
# ### in df1

# %%
df1.head(1)

# %%
# for example:

# the upper right 'check-api' bar
extract1 = df1[(~df1['wired-from']) & (df1['test']=='check-api')]

# how many entries
print(f"{extract1.shape[0]=}")

extract1.head()

# %% [markdown]
# ### in df2

# %%
# df2 is a little different

extract2 = df2[(df2['from'] == 'fping-w1-pod') & (df2['to'] == 'fping-l1-pod')]
extract2

# %% [markdown]
# ****
