#!/bin/sh
#  test/js/patch/conflict — `bin/patch.js` cherry-pick with a TRUE content
#  conflict (JS-052).  Both ours (T1) and theirs (F1) rewrite the SAME line
#  differently, so the 3-way merge frames it with `<<<<`/`||||`/`>>>>`
#  markers (left in the wt, like native — POST's POSTCFLCT is the net).
#
#       T0 ── T1          ← cur (trunk): T1 sets line 2 = Y
#         \
#          F1             ← ?feat: F1 sets line 2 = X
#
#  Asserts the fenced f.txt bytes, the `patch #<F1>` row, the `conf f.txt`
#  status row, and the restamp all match native byte-for-byte.  The clock is
#  pinned (patchcase.sh: SOURCE_DATE_EPOCH) so the commit shas — and the RGA
#  fence side order they drive — are reproducible; at this single anchor dog's
#  hash-order coincides with native's ours-first, so the native==JS differential
#  holds (cf. same-anchor-conflict, where they diverge — DOG-005).
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
# spells `cnf` in the banner AND stamps `cnf` in status — see golden.out.
patch_parity build '#@F1' f.txt
pass
