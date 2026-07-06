#!/bin/sh
#  test/js/patch/addmod — `bin/patch.js` cherry-pick where theirs ADDS a new
#  file and MODIFIES an existing one (JS-052).  Exercises the take-theirs +
#  added arms of the walk (clean, no merge needed) alongside a disjoint
#  content merge.
#
#       T0 ── T1          ← cur (trunk): T1 edits keep.txt line 1
#         \
#          F1             ← ?feat: F1 adds new.txt + edits keep.txt line 3
#
#  Asserts both files' bytes, the `patch #<F1>` row, the per-file status rows
#  (`merged keep.txt` + `applied new.txt`), and the restamp match native.
. "$(dirname "$0")/../../lib/patchcase.sh"

# TEST-003 jab-only DAG via patchcase.sh helpers (bootstrap post-alone, absolute
# `?feat` fork, `_trunk` switch by pinned t0, keeper.idx drop per op).
build() {
    printf '1\n2\n3\n4\n' > keep.txt
    _boot 't0'                                  # bootstrap trunk @ t0 (saves $BOOT)
    _fork feat                                  # label feat @ t0
    _sw feat
    printf '1\n2\nTHREE\n4\n' > keep.txt        # theirs: line 3 (disjoint)
    printf 'brand new\n' > new.txt              # theirs: a new file
    _ci 'f1' keep.txt new.txt
    F1=$(_tip feat); export F1
    _trunk                                      # back to trunk @ t0
    printf 'ONE\n2\n3\n4\n' > keep.txt          # ours: line 1
    _ci 't1' keep.txt
}

# JAB-003 golden snapshot (native oracle retired): new.txt (clean take-theirs
# ADD) reads `pat`, keep.txt's disjoint 3-way merge reads `mrg` — see golden.out.
patch_parity build '#@F1' keep.txt new.txt
pass
