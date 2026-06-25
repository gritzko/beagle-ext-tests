#!/bin/sh
#  test/js/patch/next-branch — `bin/patch.js` NEXT scope (`?<br>`): absorb a
#  branch into cur (JS-052).  theirs = the branch tip, fork = LCA(cur, theirs).
#
#       T0 ── T1          ← cur (trunk): T1 edits line 1
#         \
#          F1             ← ?feat: one commit editing line 3 (disjoint)
#
#  With feat exactly ONE commit ahead of the fork, NEXT (`?feat`) and a
#  cherry-pick of F1 absorb the same single commit.  Asserts the merged
#  f.txt bytes, the `?<F1-sha>` query-slot row, status rows, and restamp
#  match native.
. "$(dirname "$0")/../../lib/patchcase.sh"

build() {
    printf 'a\nb\nc\nd\ne\n' > f.txt
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 't0' >/dev/null 2>&1
    "$BE" put '?./feat' >/dev/null 2>&1
    "$BE" get '?..' >/dev/null 2>&1
    printf 'A\nb\nc\nd\ne\n' > f.txt
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 't1' >/dev/null 2>&1
    "$BE" get '?feat' >/dev/null 2>&1
    printf 'a\nb\nC\nd\ne\n' > f.txt
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 'f1 edit line 3' >/dev/null 2>&1
    "$BE" get '?..' >/dev/null 2>&1
}

patch_parity build '?feat' f.txt
pass
