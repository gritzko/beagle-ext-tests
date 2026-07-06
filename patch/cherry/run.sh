#!/bin/sh
#  test/js/patch/cherry — `bin/patch.js` cherry-pick (`#<sha>`) parity vs
#  native `be patch` (JS-052).  Topology:
#
#       T0 ── T1          ← cur (trunk): T1 edits line 1
#         \
#          F1             ← ?feat: F1 edits line 3 (disjoint from T1)
#
#  Cherry-picking F1 onto trunk@T1 is a disjoint 3-way merge — the result
#  carries BOTH edits (line 1 from ours, line 3 from theirs), no markers.
#  Asserts the merged f.txt bytes, the `patch #<F1>` row, the per-file
#  status row (`merged f.txt`), and the file restamp all match native.
. "$(dirname "$0")/../../lib/patchcase.sh"

# TEST-003 jab-only DAG via patchcase.sh helpers (bootstrap post-alone, absolute
# `?feat` fork, `_trunk` switch by pinned t0, keeper.idx drop per op).
build() {
    printf 'a\nb\nc\nd\ne\n' > f.txt
    _boot 't0'                                  # bootstrap trunk @ t0
    _fork feat                                  # label feat @ t0
    #  feat F1: edit line 3.
    _sw feat
    printf 'a\nb\nC\nd\ne\n' > f.txt
    _ci 'f1 edit line 3' f.txt
    F1=$(_tip feat); export F1
    #  trunk T1: edit line 1 (disjoint from feat's line 3); leaves cur on trunk.
    _trunk
    printf 'A\nb\nc\nd\ne\n' > f.txt
    _ci 't1' f.txt
}

# JAB-003 golden snapshot (native oracle retired): a clean disjoint merge
# stamps `mrg` — see golden.out.
patch_parity build '#@F1' f.txt
pass
