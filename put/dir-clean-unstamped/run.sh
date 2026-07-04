#!/bin/sh
# PUT-006 test/put/dir-clean-unstamped — `be put <dir>/` must NOT re-stage a
# tracked file that is content-clean but whose mtime is NOT in the wtlog
# stamp-set (the get-checkout state: `status` calls it `ok`).  `touch`ing a
# clean file (bytes unchanged, mtime bumped out of the stamp-set) reproduces a
# fresh store-backed get; expandDir's old mtime-only gate re-staged it, diverging
# from status.  General (not sub-specific): a plain subdir over-staged too.
. "$(dirname "$0")/../putcase.sh"

seed_baseline 'mkdir d; printf "A\n" > d/a.txt; printf "B\n" > d/b.txt'
fork_pair
# bump a.txt's mtime OUT of the stamp-set without changing its bytes (a get
# checkout leaves clean bytes on a non-stamp mtime); b.txt stays post-stamped.
mutate 'sleep 0.02; touch d/a.txt'
put_both d/

pass
