#!/bin/sh
# test/sub/keeprows — SUBS-056: mounting a sub must APPEND to its wtlog, never
# re-mint it.  `submount.mount` wrote the two-row anchor with `ulog.write`
# UNCONDITIONALLY, and `ulog.write` builds a fresh log at `<path>.tmp.<rand>`
# and renames it over the anchor — so every parent tip move discarded every row
# LOCAL to the sub (a `patch`, a `put`, a `delete`, a `post`) along with the
# work it names, breaking [Worktree]'s append-only wtlog at every mount.  The
# root does it right (get.js:446 writes only when `fresh = !exists(bePath)`).
#
# Two legs, one clone, one parent tip move:
#   (a) a `patch` absorbed INTO the mounted sub — its row and its merged bytes
#       must survive the move;
#   (b) a `put` row in the sub (staged, never committed) must survive it too.
# Plus: the anchor row keeps its ORIGINAL ts (an append, not a re-mint), and
# the checked-out sub files still read clean right after the update (the
# assigned-ts restamp must survive the switch to append).
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent

T1="$WORK/wt"
SUBWT="$T1/vendor/sub"
SUBBE="$SUBWT/.be"

_dump() {                                  # the evidence the ticket asks for
    echo "--- sub .be BEFORE the parent tip move ---"; printf '%s\n' "$BEFORE"
    echo "--- sub .be AFTER  the parent tip move ---"; cat "$SUBBE"
}
_died() { _dump; _fail "$*"; }

# ============================================================================
# 0. clone the parent: the sub mounts at pin SUBTIP0 with its two anchor rows.
# ============================================================================
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { cat "$WORK/last.err"; _fail "clone exit $_rc"; }
[ -f "$SUBBE" ] || _fail "clone: sub not mounted at $SUBWT"
[ "$(sc_subtip "$SUBWT")" = "$SUBTIP0" ] || _fail "clone: sub not at pin0"
ANCHOR0=$(awk -F'\t' 'NR==1{print $1; exit}' "$SUBBE")
[ -n "$ANCHOR0" ] || _fail "clone: sub anchor has no row 0"

# ============================================================================
# 1. UPSTREAM advance (pin-advance's step 1): a new sub commit, the fixture
#    parent absorbs it and posts, so the PARENT's gitlink pin moves — that is
#    what re-mounts the sub in the clone below.
# ============================================================================
( cd "$SUBSTORE" && printf 'sub payload v2 PATCHED\n' > lib.c \
    && "$JABC" post '#sub v2' ) >"$WORK/s2.out" 2>&1 \
    || { cat "$WORK/s2.out"; _fail "sub upstream post"; }
SUBTIP1=$(sc_tip "$SUBSTORE"); sc_is40 "$SUBTIP1" "sub tip1"
[ "$SUBTIP1" != "$SUBTIP0" ] || _fail "sub upstream tip did not advance"
( cd "$PARSTORE/vendor/sub" && "$JABC" get "file://$SUBSTORE/.be#$SUBTIP1" ) \
    >"$WORK/sadv.out" 2>&1 || { cat "$WORK/sadv.out"; _fail "advance parent's mount"; }
( cd "$PARSTORE" && "$JABC" post '#absorb sub v2' ) \
    >"$WORK/padv.out" 2>&1 || { cat "$WORK/padv.out"; _fail "parent absorb post"; }
[ "$(sc_gitlink_pin "$PARSTORE" "$SUBPATH")" = "$SUBTIP1" ] \
    || _fail "upstream gitlink not bumped to SUBTIP1"

# leg (a): absorb that commit as a PATCH into the CLONE's mounted sub — a
# `patch` row + merged bytes in the sub, nothing committed, base still at pin0.
_rc=0
( cd "$SUBWT" && "$JABC" patch "#$SUBTIP1" ) \
    >"$WORK/patch.out" 2>"$WORK/patch.err" || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/patch.err"; _fail "patch in the sub exit $_rc"; }
grep -qE "	patch	" "$SUBBE" \
    || _fail "no patch row in the sub wtlog: $(cat "$SUBBE")"
_lib=$(cat "$SUBWT/lib.c")
[ "$_lib" = "sub payload v2 PATCHED" ] || _fail "patch did not merge lib.c [$_lib]"

# ============================================================================
# 2. leg (b): a `put` row in the sub — staged, never committed.
# ============================================================================
printf 'sub helper EDITED\n' > "$SUBWT/helper.c"
_rc=0
( cd "$SUBWT" && "$JABC" put helper.c ) >"$WORK/put.out" 2>"$WORK/put.err" || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/put.err"; _fail "put in the sub exit $_rc"; }
grep -qE "	put	.*helper\.c" "$SUBBE" \
    || _fail "no put row in the sub wtlog: $(cat "$SUBBE")"

BEFORE=$(cat "$SUBBE")

# ============================================================================
# 3. move the PARENT tip and update the clone — the sub is re-mounted.
# ============================================================================
PARTIP1=$(sc_tip "$PARSTORE"); sc_is40 "$PARTIP1" "par tip1"
[ "$PARTIP1" != "$PARTIP0" ] || _fail "parent tip did not move"

_rc=0
( cd "$T1" && "$JABC" get "file://$PARSTORE/.be#$PARTIP1" ) \
    >"$WORK/g.out" 2>"$WORK/g.err" || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/g.err"; _fail "update get exit $_rc"; }
[ "$(sc_subtip "$SUBWT")" = "$SUBTIP1" ] || _fail "sub did not follow the pin advance"

# ============================================================================
# 4. THE BUG: the sub wtlog must have been APPENDED, not re-minted.
# ============================================================================
_a=$(awk -F'\t' 'NR==1{print $1; exit}' "$SUBBE")
[ "$_a" = "$ANCHOR0" ] \
    || _died "sub anchor re-minted: row 0 ts [$_a] != [$ANCHOR0] (log rewritten)"
grep -qE "	patch	" "$SUBBE" \
    || _died "SUBS-056: the sub's patch row was DISCARDED by the parent tip move"
grep -qE "	put	.*helper\.c" "$SUBBE" \
    || _died "SUBS-056: the sub's put row was DISCARDED by the parent tip move"
echo "ok   1. the sub wtlog was appended: anchor $ANCHOR0 kept, patch + put rows alive"

# the WORK those rows name survives too.
_lib=$(cat "$SUBWT/lib.c")
[ "$_lib" = "sub payload v2 PATCHED" ] \
    || _died "SUBS-056: the patched bytes were reverted: lib.c [$_lib]"
_hlp=$(cat "$SUBWT/helper.c")
[ "$_hlp" = "sub helper EDITED" ] \
    || _died "SUBS-056: the put file's bytes were reverted: helper.c [$_hlp]"
echo "ok   2. the sub's patched + staged bytes survived the parent tip move"

# ============================================================================
# 5. the real UI: `status` in the sub (and in the parent) STILL shows the
#    carried work, and the files the checkout wrote read CLEAN.  The new track
#    row de-scopes the staged set exactly as the root's get row does (GET-050
#    carry sweep), so `...V helper.c` becomes `...v helper.c` — a row either
#    way; a file that reads clean here would be the work gone silent.
# ============================================================================
ST=$(cd "$SUBWT" && "$JABC" status --plain 2>&1)
printf '%s\n' "$ST" | grep -qE '[[:space:]]helper\.c$' \
    || { _dump; echo "--- sub status ---"; printf '%s\n' "$ST"; \
         _fail "SUBS-056: the sub's carried work reads CLEAN after the update"; }
printf '%s\n' "$ST" | grep -qE '[[:space:]]lib\.c$' \
    && { echo "--- sub status ---"; printf '%s\n' "$ST"; \
         _fail "checked-out lib.c reads DIRTY right after the update (mis-stamp)"; }
ST2=$(cd "$T1" && "$JABC" status --plain 2>&1)
printf '%s\n' "$ST2" | grep -qE '[[:space:]]vendor/sub/helper\.c$' \
    || { echo "--- parent status ---"; printf '%s\n' "$ST2"; \
         _fail "parent status lost the sub's carried helper.c row"; }
echo "ok   3. status still shows the sub's carried work; the updated file is clean"

# and it is COMMITTABLE — the work is reachable, not just on disk.
_rc=0
( cd "$SUBWT" && "$JABC" post '#keep the carried edit' ) \
    >"$WORK/sp.out" 2>&1 || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/sp.out"; \
    _fail "SUBS-056: the sub's carried work is not committable after the update"; }
echo "ok   4. the carried edit still commits in the sub"

pass
