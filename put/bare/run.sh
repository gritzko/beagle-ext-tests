#!/bin/sh
# test/js/put/bare — bare `be put` (no args) parity.  Walks the baseline
# tree staging only tracked-dirty files + auto-paired system-`mv` renames;
# an untracked sibling is NEVER staged by the bare form.  Asserts native vs
# JS agree on: the auto-paired move row (written but NOT shown in the
# banner), the tracked-dirty row, the skipped untracked file, and the
# restamp.
. "$(dirname "$0")/../putcase.sh"

seed_baseline 'printf "A\n" > a.txt; printf "B\n" > b.txt'
fork_pair
mutate 'sleep 0.02; printf "A2\n" > a.txt; mv b.txt ren.txt; printf "U\n" > unt.txt'
put_both

pass
