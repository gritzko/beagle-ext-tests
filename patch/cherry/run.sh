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

build() {
    printf 'a\nb\nc\nd\ne\n' > f.txt
    "$BE" put f.txt >/dev/null 2>&1
    "$BE" post 't0' >/dev/null 2>&1
    "$BE" put '?./feat' >/dev/null 2>&1
    #  trunk T1: edit line 1 (disjoint from feat's line 3).
    "$BE" get '?..' >/dev/null 2>&1
    printf 'A\nb\nc\nd\ne\n' > f.txt
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 't1' >/dev/null 2>&1
    #  feat F1: edit line 3.
    "$BE" get '?feat' >/dev/null 2>&1
    printf 'a\nb\nC\nd\ne\n' > f.txt
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 'f1 edit line 3' >/dev/null 2>&1
    F1=$(grep -a $'\tpost\t' .be/org/refs | grep -oE '[0-9a-f]{40}' | tail -1)
    export F1
    #  back to trunk (the branch we patch INTO).
    "$BE" get '?..' >/dev/null 2>&1
}

patch_parity build '#@F1' f.txt
pass
