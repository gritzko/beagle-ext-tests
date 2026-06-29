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

build() {
    printf 'a\nb\nc\n' > f.txt
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 't0' >/dev/null 2>&1
    "$BE" put '?./feat' >/dev/null 2>&1
    "$BE" get '?..' >/dev/null 2>&1
    printf 'A\nb\nc\n' > f.txt                 # ours: line 1 = A (disjoint)
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 't1 line1=A' >/dev/null 2>&1
    "$BE" get '?feat' >/dev/null 2>&1
    printf 'a\nb\nX\nc\n' > f.txt              # F1: add X after b
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 'f1 add X' >/dev/null 2>&1
    printf 'a\nb\nc\n' > f.txt                 # F2: delete X
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 'f2 del X' >/dev/null 2>&1
    printf 'a\nb\nX\nc\n' > f.txt              # F3: re-add X
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 'f3 re-add X' >/dev/null 2>&1
    "$BE" get '?..' >/dev/null 2>&1
}

# DIS-057: JS-only goldens (patch verb untied from native be — cnf + pat/mrg/cnf
# stamp offset).  A clean re-add merge stamps `mrg`.
EXPECT_BANNER='merged f.txt'; export EXPECT_BANNER
EXPECT_STATUS='mrg f.txt'; export EXPECT_STATUS
patch_parity build '?feat!' f.txt
pass
