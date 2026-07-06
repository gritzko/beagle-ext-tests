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

# TEST-003 jab-only DAG via patchcase.sh helpers (bootstrap post-alone, absolute
# `?feat` fork, `_trunk` switch by pinned t0, keeper.idx drop per op).
build() {
    printf 'a\nb\nc\nd\ne\n' > f.txt
    _boot 't0'
    _fork feat
    _sw feat
    printf 'a\nb\nC\nd\ne\n' > f.txt
    _ci 'f1 edit line 3' f.txt
    _trunk
    printf 'A\nb\nc\nd\ne\n' > f.txt
    _ci 't1' f.txt
}

# JAB-003 golden snapshot (native oracle retired): a clean NEXT-branch absorb
# stamps `mrg` — see golden.out.
patch_parity build '?feat' f.txt
pass
