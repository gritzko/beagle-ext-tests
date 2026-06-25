#!/bin/sh
# JAB-014 parity: divergent children — trunk baseline, two branches editing
# DISJOINT lines, then the cross-branch range diff both ways.  Mirrors
# beagle/test/diff/02-divergent-children.  Exercises ref-vs-ref TREE diffs +
# the canonical `?from..to` range with branch labels (branch-FIRST resolution).
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

printf 'line one\nline two\nline three\nline four\nline five\n' > foo.c
"$BE" put foo.c >/dev/null 2>&1
"$BE" post -m base >/dev/null 2>&1

# branch fix1: create, switch, edit line one, post.
"$BE" put '?./fix1' >/dev/null 2>&1
"$BE" get '?fix1'   >/dev/null 2>&1
sleep 0.02
printf 'LINE ONE edited\nline two\nline three\nline four\nline five\n' > foo.c
"$BE" put foo.c >/dev/null 2>&1
"$BE" post -m e1 >/dev/null 2>&1

# back to trunk, branch fix2: create, switch, edit line five, post.
"$BE" get '?..'     >/dev/null 2>&1
"$BE" put '?./fix2' >/dev/null 2>&1
"$BE" get '?fix2'   >/dev/null 2>&1
sleep 0.02
printf 'line one\nline two\nline three\nline four\nLINE FIVE edited\n' > foo.c
"$BE" put foo.c >/dev/null 2>&1
"$BE" post -m e2 >/dev/null 2>&1

diff_eq "tree fix1..fix2 (canonical)" 'diff:?fix1..fix2'
diff_eq "tree fix2..fix1 (reverse)"   'diff:?fix2..fix1'
diff_eq "file fix1..fix2"             'diff:foo.c?fix1..fix2'

pass
