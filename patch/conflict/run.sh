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

build() {
    printf 'a\nb\nc\n' > f.txt
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 't0' >/dev/null 2>&1
    "$BE" put '?./feat' >/dev/null 2>&1
    "$BE" get '?..' >/dev/null 2>&1
    printf 'a\nY\nc\n' > f.txt          # ours: line 2 = Y
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 't1 line2=Y' >/dev/null 2>&1
    "$BE" get '?feat' >/dev/null 2>&1
    printf 'a\nX\nc\n' > f.txt          # theirs: line 2 = X (conflicts)
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 'f1 line2=X' >/dev/null 2>&1
    F1=$(grep -a $'\tpost\t' .be/org/refs | grep -oE '[0-9a-f]{40}' | tail -1)
    export F1
    "$BE" get '?..' >/dev/null 2>&1
}

# DIS-057: JS-only goldens (patch verb untied from native be).  A true content
# conflict spells `cnf` in the banner AND stamps `cnf` (ts+2) so `jab status`
# reads cnf — the conf→cnf rename + the conflict stamp offset.
EXPECT_BANNER='cnf f.txt'; export EXPECT_BANNER
EXPECT_STATUS='cnf f.txt'; export EXPECT_STATUS
patch_parity build '#@F1' f.txt
pass
