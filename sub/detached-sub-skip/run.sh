#!/bin/sh
# test/sub/detached-sub-skip.broken — GET-047, [/wiki/GET] "Summary of
# invocation patterns" item 4.1: a normal `get` recurs ONLY into subs attached
# to the parent's pin (track row `//…/sub#pin`, DIS-072) and IGNORES a sub
# attached DIFFERENTLY.  Here the sub is DETACHED (`get ?<sha>` inside it -> a
# refless `#<sha>` record, wtlog.attachedBranch detached=true).  The parent pin
# then advances upstream; a normal parent get updates the parent files and
# lands the new gitlink, but the detached sub's CHECKOUT and `.be` stay put.
#
# MISMATCH (unregistered — named repro.sh in a .broken dir so the CMake
# `*/*/run.sh` glob skips it): get.js mountGitlink/submount.mount never checks
# HOW the sub is attached (no attachedBranch consult), so the normal update get
# CLOBBERED the detached sub — observed: its anchor was REWRITTEN wholesale
# (the `get #<sha>` detach record destroyed, replaced by redirect +
# `///vendor/sub#<newpin>`) and lib.c went v1 -> v2.  Asserts the SPEC below;
# passes once normal-get recursion skips differently-attached subs.
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent

# ============================================================================
# 0. clone the parent; then DETACH the mounted sub at its own current commit
#    (`get ?<sha>` = D2 detach -> a bare `#<sha>` wtlog record, no track ref).
# ============================================================================
T1="$WORK/wt"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { cat "$WORK/last.err"; _fail "clone exit $_rc"; }
[ "$(sc_subtip "$T1/vendor/sub")" = "$SUBTIP0" ] || _fail "clone: sub not at pin0"

( cd "$T1/vendor/sub" && "$JABC" get "?$SUBTIP0" ) >"$WORK/det.out" 2>&1 \
    || { cat "$WORK/det.out"; _fail "detach inside the sub"; }
grep -q "	get	#$SUBTIP0\$" "$T1/vendor/sub/.be" \
    || { cat "$T1/vendor/sub/.be"; _fail "sub not detached (no #<sha> record)"; }

# ============================================================================
# 1. UPSTREAM advance: new sub commit; parent file edit post, then the absorb
#    post bumps the gitlink to SUBTIP1 (postSubs; the bump post is selective).
# ============================================================================
( cd "$SUBSTORE" && printf 'sub payload v2\n' > lib.c && "$JABC" post '#sub v2' ) \
    >"$WORK/s2.out" 2>&1 || { cat "$WORK/s2.out"; _fail "sub upstream post"; }
SUBTIP1=$(sc_tip "$SUBSTORE"); sc_is40 "$SUBTIP1" "sub tip1"
( cd "$PARSTORE" && printf 'int main(void){return 1;}\n' > main.c \
    && "$JABC" post '#parent v2' ) \
    >"$WORK/pv2.out" 2>&1 || { cat "$WORK/pv2.out"; _fail "parent v2 post"; }
( cd "$PARSTORE/vendor/sub" && "$JABC" get "file://$SUBSTORE/.be#$SUBTIP1" ) \
    >"$WORK/sadv.out" 2>&1 || { cat "$WORK/sadv.out"; _fail "advance parent's sub mount"; }
( cd "$PARSTORE" && "$JABC" post '#absorb sub v2' ) \
    >"$WORK/padv.out" 2>&1 || { cat "$WORK/padv.out"; _fail "parent absorb post"; }
PARTIP1=$(sc_tip "$PARSTORE"); sc_is40 "$PARTIP1" "par tip1"
[ "$(sc_gitlink_pin "$PARSTORE" "$SUBPATH")" = "$SUBTIP1" ] \
    || _fail "upstream gitlink not bumped to SUBTIP1"

# ============================================================================
# 2. snapshot the detached sub, then a NORMAL parent update get: the parent
#    updates + the new gitlink lands, the differently-attached sub is IGNORED.
# ============================================================================
cp -a "$T1/vendor/sub" "$WORK/sub.before"

_rc=0
( cd "$T1" && "$JABC" get "file://$PARSTORE/.be#$PARTIP1" ) \
    >"$WORK/g.out" 2>"$WORK/g.err" || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/g.err"; _fail "update get exit $_rc"; }

grep -q 'return 1' "$T1/main.c" || _fail "parent main.c not updated"
[ "$(sc_gitlink_pin "$T1" "$SUBPATH")" = "$SUBTIP1" ] \
    || _fail "new gitlink row did not land in the parent baseline"
diff -r "$WORK/sub.before" "$T1/vendor/sub" >"$WORK/sub.diff" 2>&1 \
    || { cat "$WORK/sub.diff"; \
         _fail "normal get touched a DIFFERENTLY-ATTACHED (detached) sub"; }
echo "ok   normal get: parent updated + gitlink landed, detached sub ignored"

pass
