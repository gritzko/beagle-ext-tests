#!/bin/sh
# test/get/force-untracked — GET-047 × GET.mkd 2.2 (second half): a whole-tree
# `get!` "discards local changes AND untracked files".  UNREGISTERED (.broken):
# at fe042740 the untracked half does NOT hold — the get reconcile is
# tree-driven (old vs new tree, verbs/get/get.js reconcileDir; it never scans
# the wt dir), so untracked files SURVIVE `get '!'` (observed: u.txt and
# d/u2.txt intact, tracked a.txt reset to baseline, exit 0).  MISMATCH
# evidence for GET-047; register once the untracked sweep lands.
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
gr_jclone "$SRC" "$WORK/jT"

# Dirty a tracked file AND plant untracked files at the root and in a subdir.
printf 'DIRTY-A\n'    > "$WORK/jT/a.txt"
printf 'untracked\n'  > "$WORK/jT/u.txt"
printf 'untracked2\n' > "$WORK/jT/d/u2.txt"

rc=$(gr_jget "$WORK/jT" '!')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get! exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A"          # tracked half: force-restored (HOLDS)

# SPEC 2.2 second half: untracked files are discarded too.  FAILS today —
# both survive the forceful reset.
[ ! -e "$WORK/jT/u.txt" ] \
    || _fail "get! left untracked u.txt (spec 2.2: discards untracked files)"
[ ! -e "$WORK/jT/d/u2.txt" ] \
    || _fail "get! left untracked d/u2.txt (spec 2.2: discards untracked files)"

pass
