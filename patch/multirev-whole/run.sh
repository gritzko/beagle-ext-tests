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

build() {
    printf 'a\nb\nc\nd\ne\n' > f.txt
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 't0' >/dev/null 2>&1
    "$BE" put '?./feat' >/dev/null 2>&1
    "$BE" get '?..' >/dev/null 2>&1
    printf 'A\nb\nc\nd\ne\n' > f.txt          # ours: line 1 = A
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 't1 line1=A' >/dev/null 2>&1
    "$BE" get '?feat' >/dev/null 2>&1
    printf 'a\nB\nc\nd\ne\n' > f.txt          # F1: line 2 = B
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 'f1 line2=B' >/dev/null 2>&1
    printf 'a\nB\nc\nD\ne\n' > f.txt          # F2: line 4 = D
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 'f2 line4=D' >/dev/null 2>&1
    printf 'a\nBB\nc\nD\ne\n' > f.txt         # F3: line 2 = BB (re-edit)
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 'f3 line2=BB' >/dev/null 2>&1
    "$BE" get '?..' >/dev/null 2>&1
}

# JAB-003 golden snapshot (native oracle retired): a clean multi-revision WHOLE
# absorb stamps `mrg` — see golden.out.
patch_parity build '?feat!' f.txt
pass
