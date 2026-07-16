#!/bin/sh
# test/sub/nameddel — SUBS-039/DELETE (the PUT twin): a NAMED `jab delete
# <sub-interior-path>` must delegate INTO the mounted sub — unlink there and
# stage the `delete` row in the sub's OWN wtlog — symmetric with put's
# stageInSub.  RED before: the parent engine could not see the sub file, so
# an ON-DISK interior path refused with a false DELDIRTY, and a MISSING one
# was silently "skipped" (no row anywhere).  GREEN after, both cases:
#   1. on-disk interior file  → unlinked + `delete <rest>` row in the sub;
#   2. missing interior file  → row-only sweep of that one path in the sub.
# No parent-wtlog leak, no gitlink bump (POST's job) in either case.
# TEST-003 FLAGGED: needs the JS-keeper feature — the mounted sub CHILD is
# fetched over the git/keeper WIRE (submount.mount), no keeper-free local path.
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent

T1="$WORK/get1"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { echo "--- get1 err ---"; cat "$WORK/last.err"; _fail "clone exit $_rc"; }
[ -f "$T1/vendor/sub/helper.c" ] || _fail "get1: sub not mounted/checked out"

# ---- 1. ON-DISK sub-interior file: delegate, unlink, row in the SUB wtlog ----
( cd "$T1" && "$JABC" delete vendor/sub/helper.c ) >"$WORK/del1.out" 2>"$WORK/del1.err" \
    || { cat "$WORK/del1.err"; _fail "on-disk sub delete failed (false DELDIRTY?)"; }
[ -f "$T1/vendor/sub/helper.c" ] && _fail "helper.c not unlinked"
grep -qE 'delete[[:space:]]+helper\.c' "$T1/vendor/sub/.be" \
    || _fail "no delete row in the sub wtlog: $(cat "$T1/vendor/sub/.be")"
grep -qE 'delete' "$T1/.be" \
    && _fail "delete row leaked into the parent wtlog: $(cat "$T1/.be")"
grep -q 'vendor/sub/helper\.c' "$WORK/del1.out" \
    || _fail "banner row not re-prefixed: $(cat "$WORK/del1.out")"
echo "ok   1. on-disk sub-interior delete: unlink + sub-wtlog row, no leak"

# ---- 2. MISSING sub-interior file: row-only, still into the SUB wtlog --------
rm -f "$T1/vendor/sub/lib.c"
( cd "$T1" && "$JABC" delete vendor/sub/lib.c ) >"$WORK/del2.out" 2>"$WORK/del2.err" \
    || { cat "$WORK/del2.err"; _fail "missing sub delete failed"; }
grep -qE 'delete[[:space:]]+lib\.c' "$T1/vendor/sub/.be" \
    || _fail "missing lib.c row not staged in the sub wtlog: $(cat "$T1/vendor/sub/.be")"
grep -qE 'delete' "$T1/.be" \
    && _fail "delete row leaked into the parent wtlog (case 2)"
grep -qE 'put[[:space:]]+vendor/sub#' "$T1/.be" \
    && _fail "parent gitlink bumped by delete (should be POST's job)"
echo "ok   2. missing sub-interior delete: row-only in the sub wtlog"

pass
