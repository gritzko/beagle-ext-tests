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

build() {
    printf 'a\nb\nc\n' > f.txt
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 't0' >/dev/null 2>&1
    "$BE" put '?./feat' >/dev/null 2>&1
    "$BE" get '?..' >/dev/null 2>&1
    printf 'a\nb\nC\n' > f.txt                 # ours: line 3 = C (disjoint)
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 't1 line3=C' >/dev/null 2>&1
    "$BE" get '?feat' >/dev/null 2>&1
    printf 'a1\nb\nc\n' > f.txt                # F1: line 1 = a1
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 'f1 line1=a1' >/dev/null 2>&1
    printf 'a2\nb\nc\n' > f.txt                # F2: line 1 = a2
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 'f2 line1=a2' >/dev/null 2>&1
    printf 'a3\nb\nc\n' > f.txt                # F3: line 1 = a3
    "$BE" put f.txt >/dev/null 2>&1; "$BE" post 'f3 line1=a3' >/dev/null 2>&1
    "$BE" get '?..' >/dev/null 2>&1
}

# JAB-003 golden snapshot (native oracle retired): a clean multi-edit merge
# stamps `mrg` — see golden.out.
patch_parity build '?feat!' f.txt
pass
