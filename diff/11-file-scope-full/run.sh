#!/bin/sh
# JAB-014 parity: file-scope FULL vs tree-scope WINDOWED (DIFF-003).  A 30-line
# file with one change at line 20: the file-scoped `diff:<file>?<range>` renders
# the WHOLE file (emitFull, far unchanged line 01 present), while the tree-scoped
# `diff:?<range>` stays changed-hunks-only (emitDiff, line 01 absent).  Mirrors
# beagle/test/diff/11-file-scope-full.
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

i=1; : > big.txt
while [ "$i" -le 30 ]; do printf 'line %02d original\n' "$i" >> big.txt; i=$((i + 1)); done
"$BE" put big.txt >/dev/null 2>&1
"$BE" post -m v1 '?v1' >/dev/null 2>&1

sed 's/^line 20 original$/line 20 CHANGED/' big.txt > big.txt.t && mv big.txt.t big.txt
"$BE" put big.txt >/dev/null 2>&1
"$BE" post -m v2 '?v2' >/dev/null 2>&1

# file scope: WHOLE file (full=YES) — the far line 01 must appear.
diff_eq "file scope full (range)" 'diff:big.txt?v1..v2'
# JS-071: the USER's commit:-hunk-header click target — a TWO-DOT RANGE off raw
# commit hashes (`diff:<path>?<hashA>..<hashB>`), the URI a hunk banner carries.
# Must emit the SAME real hunks as the tag-named range (range-mode reparse seam).
SHA1=$("$BE" sha1:'?v1' 2>/dev/null); SHA2=$("$BE" sha1:'?v2' 2>/dev/null)
[ -n "$SHA1" ] && [ -n "$SHA2" ] || _fail "could not resolve v1/v2 commit shas"
diff_eq "file scope full (hash range)" "diff:big.txt?$SHA1..$SHA2"
# tree scope: windowed (full=NO) — far context dropped.
diff_eq "tree scope windowed"     'diff:?v1..v2'
# file scope wt-vs-base full after a fresh edit.
sed 's/^line 05 original$/line 05 WTEDIT/' big.txt > big.txt.t && mv big.txt.t big.txt
diff_eq "file scope full (wt-vs-base)" 'diff:big.txt'

pass
