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

build() {
    printf '1\n2\n3\n4\n' > keep.txt
    "$BE" put keep.txt >/dev/null 2>&1; "$BE" post 't0' >/dev/null 2>&1
    "$BE" put '?./feat' >/dev/null 2>&1
    "$BE" get '?..' >/dev/null 2>&1
    printf 'ONE\n2\n3\n4\n' > keep.txt          # ours: line 1
    "$BE" put keep.txt >/dev/null 2>&1; "$BE" post 't1' >/dev/null 2>&1
    "$BE" get '?feat' >/dev/null 2>&1
    printf '1\n2\nTHREE\n4\n' > keep.txt        # theirs: line 3 (disjoint)
    printf 'brand new\n' > new.txt              # theirs: a new file
    "$BE" put keep.txt new.txt >/dev/null 2>&1; "$BE" post 'f1' >/dev/null 2>&1
    F1=$(grep -a $'\tpost\t' .be/org/refs | grep -oE '[0-9a-f]{40}' | tail -1)
    export F1
    "$BE" get '?..' >/dev/null 2>&1
}

# DIS-057: JS-only goldens — the JS banner spells cnf (was conf) and `jab
# status` reads the patch-stamp OFFSET as pat/mrg/cnf, so the patch verb is
# untied from native `be`.  RULING 2026-06-29: base is OURS (curTip) and the
# patched-in (theirs) tree is a SEPARATE input — so new.txt (a clean take-theirs
# ADD, absent from ours) reads `pat`, NOT `ok` (the old baselineTip-folds-theirs
# bug collapsed it).  keep.txt's disjoint 3-way merge reads `mrg`.  Status render
# order: pat before mrg.
EXPECT_BANNER='merged keep.txt\napplied new.txt'; export EXPECT_BANNER
EXPECT_STATUS='pat new.txt\nmrg keep.txt'; export EXPECT_STATUS
patch_parity build '#@F1' keep.txt new.txt
pass
