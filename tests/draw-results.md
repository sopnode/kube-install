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

```{code-cell} ipython3
import postprocess
```

```{code-cell} ipython3
df1, df2, *_ = postprocess.load("SUMMARY-05-25-18-03-41.csv")
postprocess.show_all(df1, df2)
```

```{code-cell} ipython3
df1, df2, *_ = postprocess.load("SUMMARY-05-27-07-43-50.csv")
postprocess.show_all(df1, df2)
```

```{code-cell} ipython3
latest = postprocess.latest_csv()
print(f"{latest=}")

df1, df2, *_ = postprocess.load(latest)
postprocess.show_all(df1, df2)
```
