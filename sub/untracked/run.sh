#!/bin/sh
# test/sub/untracked — GET-040 (DATA SAFETY): a plain (non-force) `jab get` that
# recurses into a submodule must MERGE/LEAVE the sub's worktree — PRESERVE an
# UNTRACKED file and a DIRTY tracked edit — and only `jab get!` (force) may
# clean-reset it.  Before the fix, the sub was checked out via checkout.apply,
# a clean-reset that unlinked EVERY path absent from the pin tree (untracked
# included) REGARDLESS of force → silent data loss ([GET-040] locus, [DIS-058]
# sub recursion must be read-only).  Force is ONE global flag, uniform across
# the root and every submodule.
# TEST-003 FLAGGED: needs the JS-keeper feature — the mounted sub CHILD is
# fetched over the git/keeper WIRE (submount.mount), no keeper-free local path.
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent

# Clone the parent; the sub mounts + checks out at vendor/sub (lib.c, helper.c).
T1="$WORK/get1"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { echo "--- get1 err ---"; cat "$WORK/last.err"; _fail "get1 exit $_rc"; }
[ -f "$T1/vendor/sub/lib.c" ] || _fail "get1: sub not mounted/checked out"

# In the mounted sub: drop an UNTRACKED file (nested dir too) + a DIRTY edit of a
# tracked file.  Neither is in the pin tree / staged.
mkdir -p "$T1/vendor/sub/scratch"
printf 'UNTRACKED\n'       > "$T1/vendor/sub/untracked.txt"
printf 'NESTED UNTRACKED\n'> "$T1/vendor/sub/scratch/note.txt"
printf 'sub payload DIRTY\n'> "$T1/vendor/sub/lib.c"   # tracked, dirty (was v1)

# ============================================================================
# 1. NON-FORCE `jab get` (recurses the sub) must PRESERVE untracked + dirty.
# ============================================================================
_rc=0
( cd "$T1" && "$JABC" get ) >"$WORK/g.out" 2>"$WORK/g.err" || _rc=$?
[ "$_rc" = 0 ] || { echo "--- get err ---"; cat "$WORK/g.err"; _fail "non-force get exit $_rc"; }

[ -f "$T1/vendor/sub/untracked.txt" ] \
    || _fail "non-force get DELETED an untracked sub file (untracked.txt) — silent data loss"
[ -f "$T1/vendor/sub/scratch/note.txt" ] \
    || _fail "non-force get DELETED a nested untracked sub file (scratch/note.txt)"
grep -q '^sub payload DIRTY$' "$T1/vendor/sub/lib.c" \
    || { echo "--- lib.c ---"; cat "$T1/vendor/sub/lib.c"; \
         _fail "non-force get CLOBBERED a dirty tracked sub file (lib.c) — not merged/left"; }
# A tracked file the user did NOT touch is still present + correct.
[ -f "$T1/vendor/sub/helper.c" ] || _fail "non-force get lost an untouched tracked sub file"
echo "ok   1. NON-FORCE: untracked (+nested) and dirty-tracked sub files PRESERVED"

# ============================================================================
# 2. FORCE `jab get!` is the sole clean-reset: untracked GONE, dirty RESET.
# ============================================================================
_rc=0
( cd "$T1" && "$JABC" get! ) >"$WORK/gf.out" 2>"$WORK/gf.err" || _rc=$?
[ "$_rc" = 0 ] || { echo "--- get! err ---"; cat "$WORK/gf.err"; _fail "force get! exit $_rc"; }

[ ! -f "$T1/vendor/sub/untracked.txt" ] \
    || _fail "get! did NOT clean the untracked sub file (force must clean-reset)"
[ ! -f "$T1/vendor/sub/scratch/note.txt" ] \
    || _fail "get! did NOT clean the nested untracked sub file"
grep -q '^sub payload v1$' "$T1/vendor/sub/lib.c" \
    || { echo "--- lib.c ---"; cat "$T1/vendor/sub/lib.c"; \
         _fail "get! did NOT reset the dirty tracked sub file to its pinned content"; }
echo "ok   2. FORCE get!: untracked cleaned + dirty tracked reset to pin"

pass
