#!/bin/sh
#  test/js/patch/readd-line — `bin/patch.js` over an ADD → DELETE → RE-ADD line
#  history (JS-052, history-sensitive parity gate).  The weave records the line
#  as inserted, then removed, then re-inserted as a DISTINCT token: only the
#  full-history fold captures the three-step provenance, where a tip-blob merge
#  would see only the net (re-added) state and could mis-anchor on the merge.
#
#       T0 ── T1                 ← cur (trunk): T1 edits line 1 (disjoint)
#         \
#          F1 ── F2 ── F3        ← ?feat: F1 ADDS line X after b, F2 DELETES it,
#                                  F3 RE-ADDS X after b again
#
#  `?feat!` absorbs the stack.  Net theirs == base + re-added X; ours edited a
#  disjoint line.  The merged f.txt and the row/status/restamp must be
#  byte-identical to native's GRAFMergeWtFileTunable result.
. "$(dirname "$0")/../../lib/patchcase.sh"

# TEST-003 jab-only DAG via patchcase.sh helpers (bootstrap post-alone, absolute
# `?feat` fork, `_trunk` switch by pinned t0, keeper.idx drop per op).
build() {
    printf 'a\nb\nc\n' > f.txt
    _boot 't0'
    _fork feat
    _sw feat
    printf 'a\nb\nX\nc\n' > f.txt              # F1: add X after b
    _ci 'f1 add X' f.txt
    printf 'a\nb\nc\n' > f.txt                 # F2: delete X
    _ci 'f2 del X' f.txt
    printf 'a\nb\nX\nc\n' > f.txt              # F3: re-add X
    _ci 'f3 re-add X' f.txt
    _trunk
    printf 'A\nb\nc\n' > f.txt                 # ours: line 1 = A (disjoint)
    _ci 't1 line1=A' f.txt
}

# JAB-003 golden snapshot (native oracle retired): a clean re-add merge stamps
# `mrg` — see golden.out.
patch_parity build '?feat!' f.txt
pass
