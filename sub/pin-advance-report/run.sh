#!/bin/sh
# test/sub/pin-advance-report — GET-047 REPORTING ruling (2026-07-16): a
# whole-tree get that ADVANCES a mounted sub's pin reports the gitlink row as
# `mod` in the PARENT hunk and relays a SEPARATE `get <subpath>` hunk listing
# the sub checkout's own changed files (status's JAB-004 relay shape, paths
# prefixed under the sub path).  A genuinely FRESH mount stays `new` (no sub
# hunk).  Fixture mirrors sub/pin-advance (attached sub, upstream pin advance,
# parent re-get); the assertions here are on the get REPORT, not the wt state.
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent

# ============================================================================
# 0. FRESH clone: the mount reports 'new vendor/sub'; NO separate sub hunk.
# ============================================================================
T1="$WORK/wt"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { cat "$WORK/last.err"; _fail "clone exit $_rc"; }
grep -qE 'new[[:space:]]+vendor/sub$' "$WORK/last.out" \
    || { cat "$WORK/last.out"; _fail "fresh mount not reported 'new vendor/sub'"; }
if grep -q '^get vendor/sub$' "$WORK/last.out"; then
    cat "$WORK/last.out"; _fail "fresh mount relayed a sub hunk (must stay new only)"
fi
echo "ok   fresh clone: mount row is new, no sub hunk"

# ============================================================================
# 1. UPSTREAM advance (as in sub/pin-advance): new sub commit, sub mount
#    re-gets it, a parent file edit, then the parent absorb post bumps the pin.
# ============================================================================
( cd "$SUBSTORE" && printf 'sub payload v2\n' > lib.c && "$JABC" post '#sub v2' ) \
    >"$WORK/s2.out" 2>&1 || { cat "$WORK/s2.out"; _fail "sub upstream post"; }
SUBTIP1=$(sc_tip "$SUBSTORE"); sc_is40 "$SUBTIP1" "sub tip1"
[ "$SUBTIP1" != "$SUBTIP0" ] || _fail "sub upstream tip did not advance"

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
# 2. UPDATE get in the clone: the report shows the pin advance as `mod
#    vendor/sub` in the parent hunk + a 'get vendor/sub' hunk with the sub's
#    changed file `upd vendor/sub/lib.c` AFTER that header.
# ============================================================================
_rc=0
( cd "$T1" && "$JABC" get "file://$PARSTORE/.be#$PARTIP1" ) \
    >"$WORK/g.out" 2>"$WORK/g.err" || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/g.err"; _fail "update get exit $_rc"; }

# sanity: the advance really happened (wt state — pin-advance owns the deep asserts).
[ "$(cat "$T1/vendor/sub/lib.c")" = "sub payload v2" ] \
    || _fail "sub lib.c did not follow the pin advance"

grep -qE 'mod[[:space:]]+vendor/sub$' "$WORK/g.out" \
    || { cat "$WORK/g.out"; _fail "pin advance not reported 'mod vendor/sub'"; }
if grep -qE 'new[[:space:]]+vendor/sub$' "$WORK/g.out"; then
    cat "$WORK/g.out"; _fail "pin advance still reported 'new vendor/sub'"
fi
grep -q '^get vendor/sub$' "$WORK/g.out" \
    || { cat "$WORK/g.out"; _fail "no separate 'get vendor/sub' hunk for the sub"; }
# the sub's changed file rides the sub hunk (after its header), prefixed.
awk '/^get vendor\/sub$/ { h = 1 }
     h && /upd[ \t]+vendor\/sub\/lib\.c$/ { found = 1 }
     END { exit !found }' "$WORK/g.out" \
    || { cat "$WORK/g.out"; _fail "sub hunk does not list upd vendor/sub/lib.c"; }
# the unchanged sub file earns NO row (checkout reports only what moved).
if grep -q 'vendor/sub/helper\.c' "$WORK/g.out"; then
    cat "$WORK/g.out"; _fail "unchanged sub file leaked into the report"
fi
echo "ok   update get: mod parent row + separate sub hunk with the sub's delta"

pass
