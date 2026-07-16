#!/bin/sh
# test/sub/selective-adv — POST-026 repro (a): a SELECTIVE post must LEAVE an
# out-of-band-ADVANCED sub ALONE when nothing is staged under it.
#
# The old postSubs force-included a sub whose classify bucket was `adv`
# (`s.bucket === "adv"` in the skip guard), so a selective parent post — staging
# only a PARENT file — still recursed the adv sub and BUMPED its gitlink pin to
# the sub's out-of-band tip.  POST-026 spec: in selective mode a sub is posted
# IFF its gitlink is `put` OR a file under it is put/deleted (transitive); an adv
# sub with no put under it is untouched (no commit, no gitlink bump).
#
# Fixture: parent + mounted vendor/sub gitlink (subcase.sh).  Stage a PARENT
# file (put main.c → selective mode) AND advance vendor/sub OUT OF BAND (a fresh
# sub commit → bucket `adv`, tip descends the pin) with NOTHING staged for it in
# the parent.  A selective parent post must commit main.c and LEAVE the gitlink
# pin at its old value (RED before the fix: the pin was bumped to the sub tip).
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent

T1="$WORK/get1"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { echo "--- get1 err ---"; cat "$WORK/last.err"; _fail "get1 exit $_rc"; }
[ -f "$T1/vendor/sub/lib.c" ] || _fail "get1: sub not mounted/checked out"

PIN0=$(sc_gitlink_pin "$T1" "$SUBPATH")
sc_is40 "$PIN0" "get1 gitlink pin0"

# --- ADVANCE vendor/sub OUT OF BAND: a fresh sub commit, tip descends the pin.
( cd "$T1/vendor/sub" && printf 'sub payload v2 OUT-OF-BAND\n' > lib.c \
    && "$JABC" post '#advance sub oob' ) >/dev/null 2>&1 || _fail "advance sub oob"
SUBTIP_ADV=$(sc_subtip "$T1/vendor/sub"); sc_is40 "$SUBTIP_ADV" "advanced sub tip"
[ "$SUBTIP_ADV" != "$PIN0" ] || _fail "fixture: sub did not advance past the pin"

# --- Make the PARENT selective: stage a PARENT file only (nothing for the sub).
printf 'int main(void){return 7;}\n' > "$T1/main.c"
( cd "$T1" && "$JABC" put main.c ) >"$WORK/put.out" 2>"$WORK/put.err" \
    || { cat "$WORK/put.err"; _fail "put main.c"; }

_rc=0
( cd "$T1" && "$JABC" post '#selective parent, leave adv sub' ) \
    >"$WORK/post.out" 2>"$WORK/post.err" || _rc=$?
[ "$_rc" = 0 ] || { echo "--- post err ---"; cat "$WORK/post.err"; \
                    echo "--- post out ---"; cat "$WORK/post.out"; _fail "post exit $_rc"; }

# THE FIX: the adv sub is UNSELECTED, so its gitlink pin stays at PIN0 (NOT
# bumped to the out-of-band sub tip).  The sub's own cur is left alone too.
PIN1=$(sc_gitlink_pin "$T1" "$SUBPATH")
[ "$PIN1" = "$PIN0" ] || _fail "selective-adv: gitlink BUMPED [$PIN0]->[$PIN1] (adv sub force-included)"
SUBTIP1=$(sc_subtip "$T1/vendor/sub")
[ "$SUBTIP1" = "$SUBTIP_ADV" ] || _fail "selective-adv: sub cur MOVED [$SUBTIP_ADV]->[$SUBTIP1]"

# The staged parent file DID land (selective committed exactly what was staged).
grep -qE 'put[[:space:]]+main\.c' "$T1/.be" \
    || _fail "selective-adv: staged parent main.c not committed"
echo "ok   selective post left the adv sub at its pin; parent file committed"

pass
