#!/bin/sh
#  test/js/patch/multirev-whole — `bin/patch.js` WHOLE scope over a MANY-commit
#  feature stack (JS-052, the history-sensitive parity gate).  The 3-blob cut
#  this rebuild replaces would diverge here: it merges only the fork/ours/theirs
#  TIP blobs, losing the intermediate commits' provenance.  Full-history
#  reconstruction folds every commit on each side into the weave.
#
#       T0 ── T1                 ← cur (trunk): T1 edits line 1
#         \
#          F1 ── F2 ── F3        ← ?feat: three commits, each editing a
#                                  DIFFERENT line (2, 4, then 2 again)
#
#  `?feat!` absorbs the whole F1..F3 stack.  ours touched line 1, theirs the
#  rest — disjoint, so the merged f.txt must combine all four edits with NO
#  conflict markers, byte-identical to native.
. "$(dirname "$0")/../../lib/patchcase.sh"

# TEST-003 jab-only DAG via patchcase.sh helpers (bootstrap post-alone, absolute
# `?feat` fork, `_trunk` switch by pinned t0, keeper.idx drop per op).
build() {
    printf 'a\nb\nc\nd\ne\n' > f.txt
    _boot 't0'
    _fork feat
    _sw feat
    printf 'a\nB\nc\nd\ne\n' > f.txt          # F1: line 2 = B
    _ci 'f1 line2=B' f.txt
    printf 'a\nB\nc\nD\ne\n' > f.txt          # F2: line 4 = D
    _ci 'f2 line4=D' f.txt
    printf 'a\nBB\nc\nD\ne\n' > f.txt         # F3: line 2 = BB (re-edit)
    _ci 'f3 line2=BB' f.txt
    _trunk
    printf 'A\nb\nc\nd\ne\n' > f.txt          # ours: line 1 = A
    _ci 't1 line1=A' f.txt
}

# JAB-003 golden snapshot (native oracle retired): a clean multi-revision WHOLE
# absorb stamps `mrg` — see golden.out.
# PATCH spec 2026-07-17: bang-less ?ref = whole missing line (URI bangs retired)
patch_parity build '?feat' f.txt
pass
