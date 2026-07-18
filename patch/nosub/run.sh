#!/bin/sh
# test/patch/nosub — PATCH.mkd 2026-07-17 §4 sub recursion: "does not recur
# with --nosub; by default: recurs".  Fixture mirrors test/sub/patch (D17):
# a parent store with a MOUNTED sub gitlink; the source then advances the sub
# (lib.c v2 + a new feature.c) AND a parent-level file (main.c) in one child
# commit THEIRS; two clones sit at the OLD pin with THEIRS seeded into their
# (frozen-copy) store.
#
#   leg A `jab patch --nosub #<THEIRS>`: the PARENT file absorbs, the sub wt
#         is NOT descended — lib.c stays v1, no feature.c appears.
#   leg B `jab patch #<THEIRS>` (default): the descent runs — the sub's
#         changed + added files land in the mount.
#
# GREEN today (patch.js: `--nosub` gates patchSubs; DIS-058 D17 descent is
# default-on).  NOTE: neither leg asserts the parent gitlink `put` bump row —
# whether patch may STAGE that bump is test/sub/patch's ground (the 2026-07-17
# "patch stages nothing" ruling), not this flag case's.
. "$(dirname "$0")/../../sub/lib/subcase.sh"

sc_build_parent

#  Freeze a COPY of the parent store; both clones ride the copy so the source
#  advance below cannot move them (the test/sub/patch isolation idiom).
PARCOPY="$WORK/par.copy"
rm -rf "$PARCOPY"; cp -a "$PARSTORE" "$PARCOPY"

A="$WORK/clone-nosub"; B="$WORK/clone-descend"
for _t in "$A" "$B"; do
    _rc=$(sc_jget "$_t" "file://$PARCOPY/.be")
    [ "$_rc" = 0 ] || { cat "$WORK/last.err"; _fail "clone exit $_rc"; }
    [ -f "$_t/vendor/sub/lib.c" ] || _fail "clone $_t: sub not checked out"
done

#  Advance the SOURCE: sub v2 + feature.c -> SUBTIP1; then ONE parent child
#  commit THEIRS bumping the gitlink AND editing main.c (so --nosub still has
#  a parent-level absorb to do).
( cd "$SUBSTORE"
  printf 'sub payload v2 ADVANCED\n' > lib.c
  printf 'sub new feature\n'         > feature.c
  "$BE" put lib.c     >/dev/null 2>&1
  "$BE" put feature.c >/dev/null 2>&1
  "$BE" post '#sub advance' >/dev/null 2>&1 ) || _fail "sub advance"
SUBTIP1=$(sc_tip "$SUBSTORE" "$SUBPROJ")
sc_is40 "$SUBTIP1" "sub tip1"
[ "$SUBTIP1" != "$SUBTIP0" ] || _fail "sub did not advance"

#  NOTE: with `put main.c` active the post goes SELECTIVE (POST-026) and won't
#  auto-fold the sub advance, and `jab put <sub>#<sha>` is a PUTNONE no-op — so
#  the gitlink bump row is STAGED directly (the sc_pin_gitlink harness idiom).
( cd "$PARSTORE"
  _r=$(awk -F'\t' 'NR==1{print $1; exit}' .be/wtlog)
  printf '%s\tget\tfile:%s/.be/?/#%s\n' "$_r" "$SUBSTORE" "$SUBTIP1" \
      > vendor/sub/.be
  printf 'sub payload v2 ADVANCED\n' > vendor/sub/lib.c
  printf 'sub new feature\n'         > vendor/sub/feature.c
  printf 'int main(void){return 1;}\n' > main.c
  "$BE" put main.c >/dev/null 2>&1 ) || _fail "parent advance (put)"
sc_pin_gitlink "$SUBPATH" "$PARSTORE/.be/wtlog" "$SUBTIP1"
( cd "$PARSTORE"
  "$BE" post '#advance sub pin + main' >/dev/null 2>&1 ) || _fail "parent advance (post)"
THEIRS=$(sc_tip "$PARSTORE" "$PARPROJ")
sc_is40 "$THEIRS" "theirs"
[ "$THEIRS" != "$PARTIP0" ] || _fail "parent did not advance"

#  Seed THEIRS' objects into the frozen copy (packs only; refs/wtlog untouched).
for _f in "$PARSTORE/.be"/*.keeper "$PARSTORE/.be"/*.keeper.idx; do
    [ -f "$_f" ] && cp "$_f" "$PARCOPY/.be/$(basename "$_f")"
done
echo "ok   fixture: clones @ old pin, THEIRS ($THEIRS) seeded"

# ---- leg A: --nosub — parent file absorbs, NO sub descent ------------------
_rc=0
( cd "$A" && "$JABC" patch --nosub "#$THEIRS" ) \
    > "$WORK/a.out" 2> "$WORK/a.err" || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/a.err"; _fail "patch --nosub exit $_rc"; }
grep -q 'return 1' "$A/main.c" \
    || _fail "--nosub: parent main.c NOT absorbed: $(cat "$A/main.c")"
[ "$(cat "$A/vendor/sub/lib.c")" = "sub payload v1" ] \
    || _fail "--nosub DESCENDED: vendor/sub/lib.c = $(cat "$A/vendor/sub/lib.c")"
[ ! -f "$A/vendor/sub/feature.c" ] \
    || _fail "--nosub DESCENDED: vendor/sub/feature.c appeared"
echo "ok   A: --nosub absorbed the parent file, left the sub alone"

# ---- leg B: default — the descent runs ------------------------------------
_rc=0
( cd "$B" && "$JABC" patch "#$THEIRS" ) \
    > "$WORK/b.out" 2> "$WORK/b.err" || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/b.err"; _fail "default patch exit $_rc"; }
grep -q 'return 1' "$B/main.c" \
    || _fail "default: parent main.c NOT absorbed: $(cat "$B/main.c")"
[ "$(cat "$B/vendor/sub/lib.c")" = "sub payload v2 ADVANCED" ] \
    || _fail "default patch did NOT descend: vendor/sub/lib.c = $(cat "$B/vendor/sub/lib.c")"
[ "$(cat "$B/vendor/sub/feature.c" 2>/dev/null)" = "sub new feature" ] \
    || _fail "default patch did NOT descend: vendor/sub/feature.c missing/wrong"
echo "ok   B: default patch descended into the mounted sub"

pass
