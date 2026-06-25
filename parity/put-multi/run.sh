#!/bin/sh
# JSQUE-007 parity case: `be put a b c` (multi-path staging) full-line byte
# parity, native vs the JS path.  Builds one committed baseline, forks a
# native + JS side, mutates BOTH identically (mod a tracked file + add an
# untracked one + a nested new file), then verb_parity asserts the `put:`
# banner, the wtlog `put` rows, and the project-shard refs rows are
# byte-identical (date column normalised only).  Flip `SUT=loop` to gate
# be/loop.js once it lands — no edit here.
. "$(dirname "$0")/../../lib/parity.sh"

seed_baseline 'printf "A\n" > a.txt; printf "B\n" > b.txt; mkdir d; printf "C\n" > d/c.txt'
fork_pair
mutate 'sleep 0.02; printf "A2\n" > a.txt; printf "N\n" > n.txt; printf "C2\n" > d/c.txt'
verb_parity put a.txt n.txt d/c.txt

pass
