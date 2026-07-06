#!/bin/sh
# TEST-003 jab-intrinsic: wt-vs-base whole-tree + single-file diffs with 3-line
# context windows over a longer file (the windowed `emitDiff` path, full=NO),
# plus an untracked file (SKIPPED — diff: is wt-vs-base) and a deletion.  Native
# `be`/`graf` RETIRED (they LAG jab); diff_eq asserts jab's own output + have/miss.
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

# a 12-line baseline so a single edit produces a windowed (not whole-file) hunk.
i=1; : > big.c
while [ "$i" -le 12 ]; do printf 'line %02d\n' "$i" >> big.c; i=$((i + 1)); done
printf 'alpha\nbeta\ngamma\n' > small.c
printf 'gone\n' > del.c
# TEST-003: bare bootstrap post (no pre-put — a leading `jab put` corrupts the
# store bootstrap; `post` auto-stages the fresh files).
"$BE" post -m base >/dev/null 2>&1

# dirty the wt: edit line 06 of big.c, edit small.c, delete del.c, add an
# untracked file (must NOT appear in the diff).
sed 's/^line 06$/line 06 CHANGED/' big.c > big.c.t && mv big.c.t big.c
printf 'alpha\nBETA mod\ngamma\n' > small.c
rm -f del.c
printf 'untracked\n' > new.c

diff_eq "wt-vs-base whole tree"   'diff:'
have '^\+line 06 CHANGED$' "whole tree: big.c edit"
have 'BETA mod'            "whole tree: small.c edit"
miss 'untracked'           "whole tree: untracked file absent (wt-vs-base)"
diff_eq "wt-vs-base file (window)" 'diff:big.c'
have '^\+line 06 CHANGED$' "file scope: the edit"
have '^ line 01$'          "file scope: far context PRESENT (whole file, DIFF-003)"
diff_eq "wt-vs-base small file"    'diff:small.c'
have 'BETA mod'            "small file: the edit"

pass
