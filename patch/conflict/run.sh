#!/bin/sh
#  test/js/patch/conflict — `bin/patch.js` cherry-pick with a TRUE content
#  conflict (JS-052).  Both ours (T1) and theirs (F1) rewrite the SAME line
#  differently.  PATCH-025/DIS-080: the merge writes the RGA LIVE reading of
#  the merged weave — both sides' tokens in weave order, NO fence markers.
#
#       T0 ── T1          ← cur (trunk): T1 sets line 2 = Y
#         \
#          F1             ← ?feat: F1 sets line 2 = X
#
#  Asserts the markerless f.txt bytes, the `patch #<F1>` row, the `con f.txt`
#  status row and the restamp.  The clock is pinned (patchcase.sh:
#  SOURCE_DATE_EPOCH) so the commit shas — and the RGA token order they drive —
#  are reproducible run-to-run.
. "$(dirname "$0")/../../lib/patchcase.sh"

# TEST-003 jab-only DAG via patchcase.sh helpers (bootstrap post-alone, absolute
# `?feat` fork, `_trunk` switch by pinned t0, keeper.idx drop per op).
build() {
    printf 'a\nb\nc\n' > f.txt
    _boot 't0'
    _fork feat
    _sw feat
    printf 'a\nX\nc\n' > f.txt          # theirs: line 2 = X (conflicts)
    _ci 'f1 line2=X' f.txt
    F1=$(_tip feat); export F1
    _trunk                              # back to trunk (the branch we patch INTO)
    printf 'a\nY\nc\n' > f.txt          # ours: line 2 = Y
    _ci 't1 line2=Y' f.txt
}

# JAB-003 golden snapshot (native oracle retired): a true content conflict
# spells `con` in the banner AND stamps `cnf` in status — see golden.out.
# PATCH spec 2026-07-17: RED until the conflict non-zero exit lands
PATCH_EXPECT=conflict
patch_parity build '#@F1' f.txt
pass
