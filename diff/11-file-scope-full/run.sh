#!/bin/sh
# DIFF-003: file-scope FULL vs tree-scope WINDOWED.  A 30-line file with one
# change at line 20: the file-scoped `diff:<file>?<range>` renders the WHOLE file
# (emitFull, far unchanged line 01 present), while the tree-scoped `diff:?<range>`
# stays changed-hunks-only (emitDiff, line 01 absent).  TEST-003: jab-intrinsic —
# native `be`/`graf` LAG jab, so assert the hunk shape jab emits, not native cmp.
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

i=1; : > big.txt
while [ "$i" -le 30 ]; do printf 'line %02d original\n' "$i" >> big.txt; i=$((i + 1)); done
# TEST-003: bare bootstrap post (no pre-put — a leading `jab put` corrupts the
# store bootstrap; `post ?v1` auto-stages the fresh file).
"$BE" post -m v1 '?v1' >/dev/null 2>&1

sed 's/^line 20 original$/line 20 CHANGED/' big.txt > big.txt.t && mv big.txt.t big.txt
"$BE" put big.txt >/dev/null 2>&1
"$BE" post -m v2 '?v2' >/dev/null 2>&1

# TEST-003: jab-intrinsic (native `be`/`graf` LAG jab, so no oracle cmp).  The
# invariant is FILE scope = WHOLE file, TREE scope = WINDOWED — asserted on the
# hunk shape jab itself emits, not on sameness to a stale native producer.

# file scope: WHOLE file (full=YES) — the change AND the far line 01 must appear.
diff_jab "file scope full (range)" 'diff:big.txt?v1..v2'
have '^\+\+\+ b/big.txt$' "file scope full (range): file header"
have '^\+line 20 CHANGED$' "file scope full (range): the change line"
have '^ line 01 original$' "file scope full (range): far context (WHOLE file)"
have '^@@ -1,30 \+1,30 @@' "file scope full (range): whole-file hunk header"

# JS-071: the USER's commit:-hunk-header click target — a TWO-DOT RANGE off raw
# commit hashes (`diff:<path>?<hashA>..<hashB>`), the URI a hunk banner carries.
# Must emit the SAME whole-file hunk as the tag-named range (range-mode reparse
# seam).  jab resolves the shas (native seeder LAGS jab, so use jab's sha1:).
SHA1=$("$JABC" sha1:'?v1' 2>/dev/null | grep -oE '^[0-9a-f]{40}$')
SHA2=$("$JABC" sha1:'?v2' 2>/dev/null | grep -oE '^[0-9a-f]{40}$')
[ -n "$SHA1" ] && [ -n "$SHA2" ] || _fail "could not resolve v1/v2 commit shas"
diff_jab "file scope full (hash range)" "diff:big.txt?$SHA1..$SHA2"
have '^\+line 20 CHANGED$' "file scope full (hash range): the change line"
have '^ line 01 original$' "file scope full (hash range): far context (WHOLE file)"

# tree scope: WINDOWED (full=NO) — the change is present but far line 01 is DROPPED.
diff_jab "tree scope windowed" 'diff:?v1..v2'
have '^\+line 20 CHANGED$' "tree scope windowed: the change line"
miss '^ line 01 original$' "tree scope windowed: far context must be dropped"

# file scope wt-vs-base full after a fresh edit — WHOLE file again (far line 01).
sed 's/^line 05 original$/line 05 WTEDIT/' big.txt > big.txt.t && mv big.txt.t big.txt
diff_jab "file scope full (wt-vs-base)" 'diff:big.txt'
have '^\+line 05 WTEDIT$'  "file scope full (wt-vs-base): the fresh edit"
have '^ line 01 original$' "file scope full (wt-vs-base): far context (WHOLE file)"

pass
