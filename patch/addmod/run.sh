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

# JAB-003 golden snapshot (native oracle retired): new.txt (clean take-theirs
# ADD) reads `pat`, keep.txt's disjoint 3-way merge reads `mrg` — see golden.out.
patch_parity build '#@F1' keep.txt new.txt
pass
