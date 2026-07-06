#!/bin/sh
# test/sub/selective — SUBS-042: selective-mode post must NOT commit an
# UNSTAGED mounted sub.  In the parent worktree in SELECTIVE (explicit-stage)
# mode (>=1 `be put`/`be delete` since the last get/post), `jab post` was
# recursing a post into EVERY mounted sub; a sub with nothing staged of its own
# ran COMMIT-ALL, rewrote its dirty files, and the parent gitlink got bumped to
# the spurious sub commit — selective intent never propagated (post.js postSubs).
#
# This case asserts the spec ([Dirty] selective = commit ONLY staged paths):
#   1. SELECTIVE parent + dirty-but-UNSTAGED sub → sub tip + parent gitlink
#      UNCHANGED, the staged PARENT file lands (the bug — RED before the fix).
#   2. COMMIT-ALL parent + dirty sub → the dirty sub STILL commits + bumps (no
#      regression of the default post-order recursion / sub/cycle).
#
# TEST-003 FLAGGED: needs the JS-keeper feature — the mounted sub CHILD is
# fetched over the git/keeper WIRE (submount.mount), no keeper-free local path.
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent

# ============================================================================
# 1. SELECTIVE: stage a PARENT file only, dirty-but-UNSTAGED edit in the sub.
# ============================================================================
T1="$WORK/get1"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { echo "--- get1 err ---"; cat "$WORK/last.err"; _fail "get1 exit $_rc"; }
[ -f "$T1/vendor/sub/lib.c" ] || _fail "get1: sub not mounted/checked out"

SUBTIP0=$(sc_subtip "$T1/vendor/sub")
PIN0=$(sc_gitlink_pin "$T1" "$SUBPATH")
sc_is40 "$SUBTIP0" "get1 sub tip0"
sc_is40 "$PIN0" "get1 gitlink pin0"
[ "$PIN0" = "$SUBTIP0" ] || _fail "get1: pin0 [$PIN0] != sub tip0 [$SUBTIP0]"

#  Make the parent SELECTIVE: an explicit `be put` of a PARENT file (edit it
#  first so the put commits real content).  THEN make a dirty-but-UNSTAGED edit
#  INSIDE the mounted sub (no `be put` inside the sub).
printf 'int main(void){return 1;}\n' > "$T1/main.c"
( cd "$T1" && "$JABC" put main.c ) >"$WORK/put.out" 2>"$WORK/put.err" \
    || { cat "$WORK/put.err"; _fail "put main.c"; }
printf 'sub payload v1 DIRTY-UNSTAGED\n' > "$T1/vendor/sub/lib.c"

_rc=0
( cd "$T1" && "$JABC" post '#selective parent only' ) \
    >"$WORK/post.out" 2>"$WORK/post.err" || _rc=$?
[ "$_rc" = 0 ] || { echo "--- post err ---"; cat "$WORK/post.err"; \
                    echo "--- post out ---"; cat "$WORK/post.out"; _fail "post exit $_rc"; }

#  THE FIX (SUBS-042): the unstaged sub must be UNTOUCHED — its cur tip stays at
#  SUBTIP0 and the parent gitlink stays at PIN0.
SUBTIP1=$(sc_subtip "$T1/vendor/sub")
PIN1=$(sc_gitlink_pin "$T1" "$SUBPATH")
[ "$SUBTIP1" = "$SUBTIP0" ] || _fail "selective: sub tip MOVED [$SUBTIP0]->[$SUBTIP1] (spurious sub commit)"
[ "$PIN1" = "$PIN0" ]       || _fail "selective: parent gitlink BUMPED [$PIN0]->[$PIN1] (spurious sub bump)"

#  The staged parent file DID land (selective committed exactly what was staged).
#  TEST-003: store-backed clone — the parent wtlog IS the `.be` FILE (rows inline).
grep -qE 'put[[:space:]]+main\.c' "$T1/.be" \
    || _fail "selective: staged parent main.c not committed"
echo "ok   1. SELECTIVE: unstaged sub left at pin; staged parent file committed"

# ============================================================================
# 2. COMMIT-ALL: a dirty sub STILL commits + bumps (no recursion regression).
# ============================================================================
#  A fresh clone, NO parent `be put` (so the parent is commit-all/implicit),
#  just a dirty edit in the sub → the default post-order recursion must commit
#  the dirty sub and bump the parent gitlink (sub/cycle behaviour preserved).
T2="$WORK/get2"
_rc=$(sc_jget "$T2" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { echo "--- get2 err ---"; cat "$WORK/last.err"; _fail "get2 exit $_rc"; }

SUBTIPA=$(sc_subtip "$T2/vendor/sub")
PINA=$(sc_gitlink_pin "$T2" "$SUBPATH")
printf 'sub payload v2 COMMIT-ALL\n' > "$T2/vendor/sub/lib.c"

_rc=0
( cd "$T2" && "$JABC" post '#commit-all' ) \
    >"$WORK/post2.out" 2>"$WORK/post2.err" || _rc=$?
[ "$_rc" = 0 ] || { echo "--- post2 err ---"; cat "$WORK/post2.err"; _fail "post2 exit $_rc"; }

SUBTIPB=$(sc_subtip "$T2/vendor/sub")
PINB=$(sc_gitlink_pin "$T2" "$SUBPATH")
sc_is40 "$SUBTIPB" "commit-all sub tipB"
[ "$SUBTIPB" != "$SUBTIPA" ] || _fail "commit-all: dirty sub did NOT commit (recursion regressed)"
[ "$PINB" = "$SUBTIPB" ]     || _fail "commit-all: parent gitlink [$PINB] != new sub tip [$SUBTIPB]"
[ "$PINB" != "$PINA" ]       || _fail "commit-all: parent gitlink not bumped off old pin"
echo "ok   2. COMMIT-ALL: dirty sub committed + parent gitlink bumped"

pass
