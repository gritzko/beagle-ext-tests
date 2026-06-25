#!/bin/sh
# test/js/delete/bare-missing — bare `be delete` (no paths) sweeps the
# baseline tree: a `delete <path>` row per tracked file gone from disk, in
# tree-walk order.  Files still on disk get no row.  Native vs JS must agree
# on the `swept N` banner, the rows (and their order), and the file set.
. "$(dirname "$0")/../deletecase.sh"

seed_baseline 'mkdir src; printf "A\n" > a.txt; printf "Z\n" > z.txt; printf "M\n" > src/m.c; printf "B\n" > src/b.c'
fork_pair
mutate 'rm a.txt z.txt src/m.c src/b.c'
delete_both

pass
