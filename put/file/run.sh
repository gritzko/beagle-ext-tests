#!/bin/sh
# test/js/put/file — `be put <file>...` (file-form staging) parity.
# Modify a tracked file + drop a new untracked one, then `be put` both:
# native vs JS must agree on the `put:` banner, the wtlog `put` rows, the
# restamp (mtime == row ts), and the file set.
. "$(dirname "$0")/../putcase.sh"

seed_baseline 'printf "A\n" > a.txt; printf "B\n" > b.txt'
fork_pair
mutate 'sleep 0.02; printf "A2\n" > a.txt; printf "N\n" > n.txt'
put_both a.txt n.txt

pass
