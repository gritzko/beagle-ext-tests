#!/bin/sh
# test/sub/patch — DIS-058 (D17): `be patch <commit>` must DESCEND into a
# MOUNTED submodule.  An absorbed commit that ADVANCES a sub (new gitlink pin +
# a changed/added sub file) must, on `jab patch <thatcommit>`:
#   (a) merge the sub's changed/added files into the mounted sub wt, and
#   (b) bump the PARENT gitlink to the new sub pin (the synthesised
#       `put <sub>#<newpin>` bump — SUBS-019 / D7 primitive),
# mirroring the post-order sub chain `be post` already does (D6/D9).
#
# Fixture: clone the parent at the OLD pin (cur trunk @ PARTIP0, sub @ SUBTIP0);
# advance the SOURCE (a new sub commit + a child parent commit THEIRS that bumps
# the gitlink); bring the advanced objects into the OLD clone's store by
# OVERWRITING its parent/sub packs with a seed clone's (full-closure) packs,
# leaving REFS/cur at the OLD pin — exactly the live `be patch <commit>` state
# (commit in the store, wt behind).  `jab patch #THEIRS` must then absorb FORWARD.
#
# RED before D17: patch.js:89/222-225 skip every gitlink, so `jab patch` leaves
# the sub UNTOUCHED — no file, no pin bump.  GREEN after the descent.
#
# Pure local `be:` keeper wire (no git, no network).  Asserts the spec, not
# native parity.  Builds in its OWN scratch dirs (subcase.sh $WORK).
. "$(dirname "$0")/../lib/subcase.sh"

# --- build the parent+sub fixture (parent gitlink @ SUBTIP0) -----------------
sc_build_parent

# ============================================================================
# 1. Clone the parent at the CURRENT tip (PARTIP0, sub @ SUBTIP0) BEFORE the
#    advance — the `be:` wire clones the advertised tip, so the clone must
#    precede the advance to land REFS/cur at the OLD pin.
# ============================================================================
T1="$WORK/clone"
_rc=$(sc_jget "$T1" "be:$PARSTORE/.be?/par")
[ "$_rc" = 0 ] || { echo "--- clone err ---"; cat "$WORK/last.err"; _fail "clone exit $_rc"; }
[ -f "$T1/vendor/sub/lib.c" ]      || _fail "clone: sub not checked out"
[ ! -f "$T1/vendor/sub/feature.c" ] || _fail "clone: advanced sub file already present"
PIN0=$(sc_gitlink_pin "$T1" "$SUBPATH")
[ "$PIN0" = "$SUBTIP0" ] || _fail "clone: gitlink pin [$PIN0] != old [$SUBTIP0]"

# ============================================================================
# 2. In the SOURCE stores: advance the sub (v2 + a NEW sub file) -> SUBTIP1, then
#    make a NEW parent commit (child of PARTIP0) THEIRS that bumps the gitlink.
# ============================================================================
( cd "$SUBSTORE"
  printf 'sub payload v2 ADVANCED\n' > lib.c
  printf 'sub new feature\n'         > feature.c
  "$BE" put lib.c     >/dev/null 2>&1
  "$BE" put feature.c >/dev/null 2>&1
  "$BE" post '#sub advance' >/dev/null 2>&1 ) || _fail "sub advance"
SUBTIP1=$(sc_tip "$SUBSTORE" "$SUBPROJ")
sc_is40 "$SUBTIP1" "sub tip1"
[ "$SUBTIP1" != "$SUBTIP0" ] || _fail "sub did not advance"

( cd "$PARSTORE"
  _r=$(awk -F'\t' 'NR==1{print $1; exit}' .be/wtlog)
  printf '%s\tget\tfile:%s/.be/?/sub#%s\n' "$_r" "$SUBSTORE" "$SUBTIP1" \
      > vendor/sub/.be
  printf 'sub payload v2 ADVANCED\n' > vendor/sub/lib.c
  printf 'sub new feature\n'         > vendor/sub/feature.c
  "$BE" put "vendor/sub#$SUBTIP1" >/dev/null 2>&1
  "$BE" post '#advance sub pin' >/dev/null 2>&1 ) || _fail "parent advance"
THEIRS=$(sc_tip "$PARSTORE" "$PARPROJ")
sc_is40 "$THEIRS" "theirs (parent advance commit)"
[ "$THEIRS" != "$PARTIP0" ] || _fail "parent did not advance"
echo "ok   1. clone @ old pin ($SUBTIP0); source advanced: sub tip1 ($SUBTIP1), theirs ($THEIRS)"

# ============================================================================
# 3. Seed the advanced objects into the OLD clone's store: a throwaway clone at
#    the (now advanced) tip THEIRS holds the FULL closure (PARTIP0+THEIRS+SUBTIP0
#    +SUBTIP1); OVERWRITE the old clone's par/sub packs with it.  REFS/cur stay at
#    the OLD pin (refs are NOT copied) — THEIRS becomes locally resolvable while
#    cur/wt sit behind it.
# ============================================================================
T3="$WORK/seed"
_rc=$(sc_jget "$T3" "be:$PARSTORE/.be?/par")
[ "$_rc" = 0 ] || { echo "--- seed err ---"; cat "$WORK/last.err"; _fail "seed exit $_rc"; }
for _proj in par sub; do
    [ -d "$T3/.be/$_proj" ] || continue
    mkdir -p "$T1/.be/$_proj"
    # overwrite packs + idx with the full-closure seed (drop the old idx first so
    # no stale file_id mapping survives), keep the old REFS untouched.
    rm -f "$T1/.be/$_proj"/*.keeper "$T1/.be/$_proj"/*.idx 2>/dev/null
    for _f in "$T3/.be/$_proj"/*.keeper "$T3/.be/$_proj"/*.idx; do
        [ -f "$_f" ] && cp "$_f" "$T1/.be/$_proj/$(basename "$_f")"
    done
done
# cur/wt still at the OLD pin (trunk gitlink SUBTIP0, no advanced file on disk).
PIN0B=$(sc_gitlink_pin "$T1" "$SUBPATH")
[ "$PIN0B" = "$SUBTIP0" ] || _fail "seed disturbed cur pin [$PIN0B] != old [$SUBTIP0]"
[ ! -f "$T1/vendor/sub/feature.c" ] || _fail "seed disturbed the wt (feature.c present)"
echo "ok   2. old clone store seeded with THEIRS + SUBTIP1, cur/wt still @ old pin"

# ============================================================================
# 4. THE GAP (D17): `jab patch #<THEIRS>` must descend the mounted sub.
# ============================================================================
_rc=0
( cd "$T1" && "$JABC" patch "#$THEIRS" ) >"$WORK/patch.out" 2>"$WORK/patch.err" || _rc=$?
[ "$_rc" = 0 ] || { echo "--- patch err ---"; cat "$WORK/patch.err"; \
                    echo "--- patch out ---"; cat "$WORK/patch.out"; _fail "patch exit $_rc"; }

# (a) the sub's changed + new files landed in the mount (the sub merge descended).
[ -f "$T1/vendor/sub/feature.c" ] \
    || { echo "--- patch out ---"; cat "$WORK/patch.out"; \
         _fail "D17: sub new file vendor/sub/feature.c NOT created by patch (no descent)"; }
_got=$(cat "$T1/vendor/sub/feature.c")
[ "$_got" = "sub new feature" ] \
    || _fail "D17: vendor/sub/feature.c [$_got] != [sub new feature]"
_lib=$(cat "$T1/vendor/sub/lib.c")
[ "$_lib" = "sub payload v2 ADVANCED" ] \
    || _fail "D17: vendor/sub/lib.c [$_lib] != advanced v2 (sub merge did not descend)"
echo "ok   3a. patch descended: the sub's changed + new files landed in the mount"

# (b) the PARENT gitlink bumped to the advanced sub pin (the synthesised
#     `put <sub>#<newpin>` D7 bump) — recorded in the wtlog.
grep -qE "put[[:space:]]+vendor/sub#$SUBTIP1" "$T1/.be/wtlog" \
    || { echo "--- wtlog ---"; cat "$T1/.be/wtlog"; \
         _fail "D17: no 'put vendor/sub#$SUBTIP1' gitlink bump in the wtlog (D7)"; }
echo "ok   3b. patch bumped the parent gitlink to the advanced sub pin ($SUBTIP1)"

pass
