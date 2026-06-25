#!/bin/sh
# JAB-014 parity: wt-vs-base whole-tree + single-file diffs with 3-line context
# windows over a longer file (the windowed `emitDiff` path, full=NO), plus an
# untracked file (SKIPPED — diff: is wt-vs-base, not wt-vs-empty) and a
# deletion.  Mirrors beagle/test/diff/03-stock-context.
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

# a 12-line baseline so a single edit produces a windowed (not whole-file) hunk.
i=1; : > big.c
while [ "$i" -le 12 ]; do printf 'line %02d\n' "$i" >> big.c; i=$((i + 1)); done
printf 'alpha\nbeta\ngamma\n' > small.c
printf 'gone\n' > del.c
"$BE" put big.c small.c del.c >/dev/null 2>&1
"$BE" post -m base >/dev/null 2>&1

# dirty the wt: edit line 06 of big.c, edit small.c, delete del.c, add an
# untracked file (must NOT appear in the diff).
sed 's/^line 06$/line 06 CHANGED/' big.c > big.c.t && mv big.c.t big.c
printf 'alpha\nBETA mod\ngamma\n' > small.c
rm -f del.c
printf 'untracked\n' > new.c

diff_eq "wt-vs-base whole tree"   'diff:'
diff_eq "wt-vs-base file (window)" 'diff:big.c'
diff_eq "wt-vs-base small file"    'diff:small.c'

pass
