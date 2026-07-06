#!/bin/sh
#  test/js/patch/multiedit-line — `bin/patch.js` over a line MODIFIED ACROSS
#  MANY commits (JS-052, history-sensitive parity gate).  The same line is
#  rewritten on F1, F2, F3; each fold supersedes the prior token.  Only the
#  full-history reconstruction replays all three; a tip-blob merge sees just
#  the last value and can lose the intermediate anchoring native preserves.
#
#       T0 ── T1                 ← cur (trunk): T1 edits line 3 (disjoint)
#         \
#          F1 ── F2 ── F3        ← ?feat: line 1 rewritten v1→v2→v3
#
#  ours edits a disjoint line, theirs converges line 1 on v3 over three
#  commits.  Merged f.txt + row + status + restamp must match native.
. "$(dirname "$0")/../../lib/patchcase.sh"

# TEST-003 jab-only DAG via patchcase.sh helpers (bootstrap post-alone, absolute
# `?feat` fork, `_trunk` switch by pinned t0, keeper.idx drop per op).
build() {
    printf 'a\nb\nc\n' > f.txt
    _boot 't0'
    _fork feat
    _sw feat
    printf 'a1\nb\nc\n' > f.txt                # F1: line 1 = a1
    _ci 'f1 line1=a1' f.txt
    printf 'a2\nb\nc\n' > f.txt                # F2: line 1 = a2
    _ci 'f2 line1=a2' f.txt
    printf 'a3\nb\nc\n' > f.txt                # F3: line 1 = a3
    _ci 'f3 line1=a3' f.txt
    _trunk
    printf 'a\nb\nC\n' > f.txt                 # ours: line 3 = C (disjoint)
    _ci 't1 line3=C' f.txt
}

# JAB-003 golden snapshot (native oracle retired): a clean multi-edit merge
# stamps `mrg` — see golden.out.
patch_parity build '?feat!' f.txt
pass
