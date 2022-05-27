#!/bin/bash

FITNODE="$1"; shift
[[ -z "$FITNODE" ]] && { echo "you must specify fitnode on the command line, e.g. fit01"; exit 1; }

HOSTS="sopnode-w2.inria.fr sopnode-w3.inria.fr $FITNODE"

SUMMARY="SUMMARY-$(date +%m-%d-%H-%M-%S).csv"
rm -f $SUMMARY

for h in $HOSTS; do
    rsync -ai root@$h:TESTS.csv TESTS-$h.csv
    cat TESTS-$h.csv >> $SUMMARY
done

cat << EOF
ipython
import postprocess
df1, df2, df2_straight, df2_cross = postprocess.load("$SUMMARY")
EOF
