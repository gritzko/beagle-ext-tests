#!/bin/sh
# test/js/delete/dirty — `be delete <file>` on an untracked / user-edited
# file (mtime ∉ stamp-set) refuses DELDIRTY: the file stays on disk, no row
# is appended, exit is non-zero.  An earlier clean arg in the same call IS
# unlinked + row'd before the refusal.  Native vs JS (mtime-only gate, DEL.c
# :492) must agree on stdout, the partial row, and the file set.
. "$(dirname "$0")/../deletecase.sh"

seed_baseline 'printf "A\n" > a.txt'
fork_pair
mutate 'sleep 0.02; printf "stray\n" > stray.txt'
delete_both a.txt stray.txt

pass
