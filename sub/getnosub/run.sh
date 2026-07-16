#!/bin/sh
# test/sub/getnosub.broken — GET-047, [/wiki/GET] "Summary of invocation
# patterns" item 4.0: `get --nosub` does NOT recur into submodules.  On an
# update get of a parent whose pin advanced (parent file + gitlink bump), the
# parent files update but the mounted attached sub stays COMPLETELY untouched —
# checkout bytes AND its `.be` anchor byte-identical (`--nosub` spelling per
# diff/status/patch/post; be.flags via core/loop.js).
#
# MISMATCH (unregistered — named repro.sh in a .broken dir so the CMake
# `*/*/run.sh` glob skips it): verbs/get/get.js never reads `--nosub` off
# be.flags (grep: no `nosub` hit in verbs/get or shared/submount.js), so
# `jab get --nosub file://<par>/.be#<tip1>` still MOUNTS the sub — observed:
# the sub anchor was rewritten to `///vendor/sub#<newpin>` and lib.c went
# v1 -> v2.  Asserts the SPEC below; passes once the flag gates recursion.
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent

# ============================================================================
# 0. clone the parent at PARTIP0: the sub mounts ATTACHED to pin SUBTIP0.
# ============================================================================
T1="$WORK/wt"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { cat "$WORK/last.err"; _fail "clone exit $_rc"; }
[ "$(sc_subtip "$T1/vendor/sub")" = "$SUBTIP0" ] || _fail "clone: sub not at pin0"

# ============================================================================
# 1. UPSTREAM advance: new sub commit; parent commits a file edit, then absorbs
#    the advanced sub (gitlink bump) — two posts, the absorb one is selective.
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
# 2. snapshot the mounted sub (checkout + .be anchor), then `get --nosub`.
# ============================================================================
cp -a "$T1/vendor/sub" "$WORK/sub.before"

_rc=0
( cd "$T1" && "$JABC" get --nosub "file://$PARSTORE/.be#$PARTIP1" ) \
    >"$WORK/g.out" 2>"$WORK/g.err" || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/g.err"; _fail "get --nosub exit $_rc"; }

grep -q 'return 1' "$T1/main.c" || _fail "--nosub: parent main.c not updated"
diff -r "$WORK/sub.before" "$T1/vendor/sub" >"$WORK/sub.diff" 2>&1 \
    || { cat "$WORK/sub.diff"; \
         _fail "--nosub recursed: mounted sub NOT byte-identical (checkout or .be changed)"; }
echo "ok   --nosub: parent updated, mounted sub untouched (checkout + .be identical)"

pass
