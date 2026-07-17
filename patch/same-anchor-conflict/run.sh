#!/bin/sh
#  test/js/patch/same-anchor-conflict — `bin/patch.js` CONCURRENT edits at the
#  SAME anchor on both branches, each over MULTIPLE commits (JS-052,
#  history-sensitive parity gate).  Both sides insert/rewrite at the line after
#  `b`; the weave's RGA tie-break (commit-id DESC) decides the in-frame order,
#  so the fence ordering is a pure function of the real commit ids — the exact
#  thing dog's WEAVEMerge must reproduce identically to native to pass.
#
#       T0 ── T1 ── T2           ← cur (trunk): two commits both editing line 2
#         \
#          F1 ── F2              ← ?feat: two commits both editing line 2
#
#  Both sides end with a DIFFERENT line-2 value at the same anchor → a true
#  conflict.  The merged f.txt carries `<<<<`/`||||`/`>>>>` fences.  The clock
#  is pinned (patchcase.sh: SOURCE_DATE_EPOCH) so the commit shas — and thus
#  dog's RGA hash-order side ordering — are reproducible.
#
#  DOG-005 residual: native `be patch` runs graf's GRAFMergeWtFileTunable,
#  which builds the OURS weave then lays theirs on as one edit → ours always
#  framed first.  dog's symmetric WEAVEMerge orders sides by the commit-id
#  RGA tie-break (hash-order, ruled CORRECT) → here theirs (X2) frames first.
#  So native and JS legitimately differ on side ORDER until graf retires;
#  this case gates JS against the fixed dog golden, not native (patch_js_golden
#  still asserts row + conf banner match native).  Converges with DOG-005.
. "$(dirname "$0")/../../lib/patchcase.sh"

# TEST-003 jab-only DAG via patchcase.sh helpers (bootstrap post-alone, absolute
# `?feat` fork, `_trunk` switch by pinned t0, keeper.idx drop per op).
build() {
    printf 'a\nb\nc\n' > f.txt
    _boot 't0'
    _fork feat
    _sw feat
    printf 'a\nX1\nc\n' > f.txt                # theirs F1: line 2 = X1
    _ci 'f1 line2=X1' f.txt
    printf 'a\nX2\nc\n' > f.txt                # theirs F2: line 2 = X2
    _ci 'f2 line2=X2' f.txt
    _trunk
    printf 'a\nO1\nc\n' > f.txt                # ours T1: line 2 = O1
    _ci 't1 line2=O1' f.txt
    printf 'a\nO2\nc\n' > f.txt                # ours T2: line 2 = O2
    _ci 't2 line2=O2' f.txt
}

# JAB-003 golden snapshot: dog frames theirs (X2) before ours (O2) at this
# anchor; the committed golden captures jab's verified fence order + banner.
# BRO-030: golden pins the DERIVED patch col (..v!); WHOLE `?<sha>!` renders ...!
# today — refOf/patchTheirs drops the `!`-suffixed theirs sha (suspected reporter bug).
patch_js_golden build '?feat!' f.txt
pass
