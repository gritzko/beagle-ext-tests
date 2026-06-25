#!/bin/sh
# test/js/put/dir — `be put <dir>/` (dir-form expansion) parity.  A tracked
# subtree with one modified file + one new file: the dir-form must expand to
# one `put` row per tracked-dirty / untracked file in lex order (clean
# siblings skipped), identically native vs JS.
. "$(dirname "$0")/../putcase.sh"

seed_baseline 'mkdir d; printf "C\n" > d/c.txt; printf "E\n" > d/e.txt'
fork_pair
mutate 'sleep 0.02; printf "C2\n" > d/c.txt; printf "F\n" > d/f.txt'
put_both d/

pass
