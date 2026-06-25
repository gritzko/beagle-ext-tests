#!/bin/sh
# test/js/put/unchanged — multi-arg `be put` where one named path is
# baseline-clean.  The clean path reports `is unchanged — skipped` ON STDOUT
# (inside the `put:` banner), the dirty path stages a row; native vs JS must
# agree on the interleaved banner + the single `put` row.
. "$(dirname "$0")/../putcase.sh"

seed_baseline 'printf "U\n" > unchanged.txt; printf "M\n" > to-modify.txt'
fork_pair
mutate 'sleep 0.02; printf "M2\n" > to-modify.txt'
put_both unchanged.txt to-modify.txt

pass
