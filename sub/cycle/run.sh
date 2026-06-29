#!/bin/sh
# test/sub/cycle — DIS-058 (D1-D9): the JS get/post submodule RECURSION cycle.
# A parent store COMMITS a sub as a gitlink (+ `.gitmodules`).  The cycle:
#
#   1. GET (pre-order): `jab get be:<parstore>?/par` clones the parent AND
#      mounts the sub — fetches the child shard from the SAME source, clones it
#      as a sibling shard, writes the sub wtlog anchor (<wt>/<path>/.be), and
#      checks out the commit named by the parent gitlink.  Assert the sub is on
#      disk + the anchor exists + the sub files match the pinned commit.
#   2. POST (post-order): edit a file INSIDE the mounted sub, then `jab post`.
#      The recursion commits the dirty child FIRST (a NEW child commit), then
#      records the child commit sha into the parent gitlink, then commits the
#      parent.  Assert the sub tip ADVANCED and the parent gitlink BUMPED to it.
#   3. RE-GET: a fresh clone reproduces the nested tree at the new pins.
#
# Pure local `be:` keeper wire (no git, no network).  Asserts the spec, not
# native parity.  RED before DIS-058; green after.
. "$(dirname "$0")/../lib/subcase.sh"

# --- build the parent+sub fixture -------------------------------------------
sc_build_parent

# ============================================================================
# 1. GET pre-order: clone the parent, mount + checkout the sub.
# ============================================================================
T1="$WORK/get1"
_rc=$(sc_jget "$T1" "be:$PARSTORE/.be?/par")
[ "$_rc" = 0 ] || { echo "--- get1 err ---"; cat "$WORK/last.err"; _fail "get1 exit $_rc"; }

# parent files present.
[ -f "$T1/main.c" ]       || _fail "get1: parent main.c missing"
# .gitmodules carried through.
[ -f "$T1/.gitmodules" ]  || _fail "get1: .gitmodules missing"
# THE GAP (D2-D5): the sub must be mounted + checked out.
[ -f "$T1/vendor/sub/.be" ] || _fail "get1: sub mount anchor <wt>/vendor/sub/.be missing (D2/D13)"
[ -f "$T1/vendor/sub/lib.c" ]    || _fail "get1: sub lib.c not checked out (D2)"
[ -f "$T1/vendor/sub/helper.c" ] || _fail "get1: sub helper.c not checked out (D2)"
_got=$(cat "$T1/vendor/sub/lib.c")
[ "$_got" = "sub payload v1" ] || _fail "get1: sub lib.c content [$_got] != [sub payload v1] (D3 pin checkout)"

# the mounted sub's cur tip == the parent gitlink pin (D3).
PIN1=$(sc_gitlink_pin "$T1" "$SUBPATH")
sc_is40 "$PIN1" "get1 gitlink pin"
[ "$PIN1" = "$SUBTIP0" ] || _fail "get1: gitlink pin [$PIN1] != sub tip0 [$SUBTIP0]"
SUBTIP_MOUNT=$(sc_subtip "$T1/vendor/sub")
sc_is40 "$SUBTIP_MOUNT" "get1 mounted sub tip"
[ "$SUBTIP_MOUNT" = "$SUBTIP0" ] || _fail "get1: mounted sub tip [$SUBTIP_MOUNT] != pin [$SUBTIP0]"
echo "ok   1. GET pre-order: sub mounted + checked out at the parent gitlink pin"

# ============================================================================
# 2. POST post-order: edit the sub, post recursively → child commit + bump.
# ============================================================================
printf 'sub payload v2 EDITED\n' > "$T1/vendor/sub/lib.c"

# Stage + post from the PARENT wt; the recursion must descend into the dirty sub.
( cd "$T1" && "$JABC" put vendor/sub/lib.c ) >"$WORK/put.out" 2>"$WORK/put.err" || true
_rc=0
( cd "$T1" && "$JABC" post '#bump sub' ) >"$WORK/post.out" 2>"$WORK/post.err" || _rc=$?
[ "$_rc" = 0 ] || { echo "--- post err ---"; cat "$WORK/post.err"; \
                    echo "--- post out ---"; cat "$WORK/post.out"; _fail "post exit $_rc"; }

# the CHILD got its OWN new commit (sub tip advanced past SUBTIP0).
SUBTIP1=$(sc_subtip "$T1/vendor/sub")
sc_is40 "$SUBTIP1" "post sub tip1"
[ "$SUBTIP1" != "$SUBTIP0" ] || _fail "post: sub tip did NOT advance (D6 no child commit)"

# the PARENT gitlink BUMPED to the new child commit (D7 auto).
PIN2=$(sc_gitlink_pin "$T1" "$SUBPATH")
sc_is40 "$PIN2" "post gitlink pin"
[ "$PIN2" = "$SUBTIP1" ] || _fail "post: parent gitlink [$PIN2] != new sub tip [$SUBTIP1] (D7 bump)"
[ "$PIN2" != "$SUBTIP0" ] || _fail "post: parent gitlink not bumped off the old pin (D7)"

# the parent advanced too (a new parent commit recording the bump).
PARTIP1=$(sc_tip "$T1" "$PARPROJ")
sc_is40 "$PARTIP1" "post par tip1"
[ "$PARTIP1" != "$PARTIP0" ] || _fail "post: parent tip did NOT advance"
echo "ok   2. POST post-order: child commit ($SUBTIP1) + parent gitlink bump"

# ============================================================================
# 3. RE-GET: a fresh clone reproduces the nested tree at the new pins.
# ============================================================================
# Re-clone the PARENT from T1's own store (it is a primary `be:` store now).
T2="$WORK/get2"
_rc=$(sc_jget "$T2" "be:$T1/.be?/par")
[ "$_rc" = 0 ] || { echo "--- get2 err ---"; cat "$WORK/last.err"; _fail "get2 exit $_rc"; }
[ -f "$T2/vendor/sub/.be" ]   || _fail "get2: sub mount anchor missing on re-clone"
_got=$(cat "$T2/vendor/sub/lib.c")
[ "$_got" = "sub payload v2 EDITED" ] || _fail "get2: sub lib.c [$_got] != edited v2 (re-clone at new pin)"
PIN3=$(sc_gitlink_pin "$T2" "$SUBPATH")
[ "$PIN3" = "$SUBTIP1" ] || _fail "get2: re-cloned gitlink [$PIN3] != new sub tip [$SUBTIP1]"
echo "ok   3. RE-GET: nested tree reproduced at the bumped pins"

pass
