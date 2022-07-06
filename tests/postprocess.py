from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


def latest_csv():
    return sorted(Path(".").glob("SUMM*.csv"),
                  key = lambda path: path.stat().st_mtime)[-1]

def load(filename):
    """
    df1 is about tests that go out of the cluster (dns, http)

    df2 is about the tests that have both ends in the cluster
    and just in case we split this again into 2 parts
    df2_straight: the test remains on one side
    df2_cross: the test involves a crossing from one side to the other
    """
    df = pd.read_csv(filename, sep=';', names=['test','from','to','success','date'])

    df_version = df[df.test == 'version']

    # remove the check-all entries that are not atomic
    df = df[~(df.test.isin(['check-all', 'version']))]
    # normalize success as a bool
    df.success = df.success == "OK"

    # true if the test was originating on the wired side
    df['wired-from'] = (df['from'].str.contains("w2")
                      | df['from'].str.contains("w3"))

    # split into 2
    # check-dns and check-http are really checking against the outside world
    # so it's not something that can be classified into cross or straight
    single_tests = df.test.isin(("check-api", "check-dns", "check-http"))
    df1 = df[single_tests].copy()
    df2 = df[~single_tests].copy()

    # true if the test was targeting the wired side
    df2['wired-to'] = (df2['to'].str.contains("w2")
                     | df2['to'].str.contains("w3")
                     | df2['to'].str.contains("10.244"))
    # true if the test was crossing boundaries
    df2['cross'] = df2['wired-from'] != df2['wired-to']

    #df2_straight = df2[~df2.cross]
    #df2_cross = df2[df2.cross]

    return df1, df2, df_version


def draw_df1(df1, lax, rax):

    df1 = df1[['test', 'success', 'wired-from']]
    #measures = df1.test.unique()
    lhs = df1[df1['wired-from']][['test', 'success']]
    rhs = df1[~df1['wired-from']][['test', 'success']]

    lax.set_title("from wired")
    lax.set_ylim((0, 1))
    rax.set_title("from wireless")
    rax.set_ylim((0, 1))

    lhs.groupby('test').mean().plot.bar(ax=lax)
    rhs.groupby('test').mean().plot.bar(ax=rax)


def draw_df2(df2, ulax, urax, llax, lrax):

    df2 = df2[['test', 'success', 'wired-from', 'wired-to']]
    #measures = df2.test.unique()
    ul = df2[ df2['wired-from']   &   df2['wired-to' ]][['test', 'success']]
    ur = df2[(~df2['wired-from']) &   df2['wired-to' ]][['test', 'success']]
    ll = df2[ df2['wired-from']   & (~df2['wired-to'])][['test', 'success']]
    lr = df2[(~df2['wired-from']) & (~df2['wired-to'])][['test', 'success']]

    ulax.set_title("wired -> wired")
    ulax.set_ylim((0, 1))
    urax.set_title("wireless -> wired")
    urax.set_ylim((0, 1))
    llax.set_title("wired -> wireless")
    llax.set_ylim((0, 1))
    lrax.set_title("wireless -> wireless")
    lrax.set_ylim((0, 1))

    ul.groupby('test').mean().plot.bar(ax=ulax)
    ur.groupby('test').mean().plot.bar(ax=urax)
    ll.groupby('test').mean().plot.bar(ax=llax)
    lr.groupby('test').mean().plot.bar(ax=lrax)

def display_df_version(df_version):
    df = (df_version
            .rename(columns={'success': 'version', 'from': 'hostname', 'to': 'rpm'})
            .pivot_table('version', index='hostname', columns='rpm', aggfunc='first')
    )
    display(df)


def show_all(df1, df2):

    fig, ((l1, r1), (l2, r2), (l3, r3)) = plt.subplots(3, 2)

    draw_df1(df1, l1, r1)
    draw_df2(df2, l2, r2, l3, r3)
    fig.tight_layout()

def show_file(filename):
    df1, df2, df_version = load(filename)
    show_all(df1, df2)
    display_df_version(df_version)
    return df1, df2
