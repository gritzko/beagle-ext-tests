#!/bin/sh
# test/sub/pinuri — DIS-072 (RULED 2026-07-15, [DIS-071] law #4): a mounted sub
# tracks the PARENT'S PIN by its own local URI `//WT/path/to/sub#<pin>` — no
# synthetic `.parent` branch, no refs entry.
#   1. the MOUNT records `get //WT/path/to/sub#<pin>` (here `///vendor/sub`,
#      the clone being its own root), never `?/sub/.par...#<pin>`;
#   2. the sub's OWN commit advances the sub wt only and moves NO ref;
#   3. the PARENT's post bumps the gitlink AND re-attaches the child by a
#      fresh `//WT/path/to/sub#<newpin>` row in the CHILD's wtlog — still no ref.
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent     # par -> vendor/sub (gitlink + .gitmodules committed)

# refs snapshot helper: the sub's shard is the SUBSTORE (local-source reuse).
_refs() { [ -f "$SUBSTORE/.be/refs" ] && od -An -c "$SUBSTORE/.be/refs" | tr -d ' \n' || printf 'norefs'; }

T1="$WORK/t1"
rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$rc" = 0 ] || { cat "$WORK/last.err" >&2; _fail "clone parent rc=$rc"; }
[ -f "$T1/vendor/sub/lib.c" ] || _fail "sub not mounted"

# --- 1. the mount record is the pin URI, not a synthetic branch -------------
ANCH=$(od -An -c "$T1/vendor/sub/.be" | tr -d ' \n')
case "$ANCH" in
  *"///vendor/sub#$SUBTIP0"*) ;;
  *) _fail "mount did not record ///vendor/sub#$SUBTIP0: $(cat "$T1/vendor/sub/.be")" ;;
esac
case "$ANCH" in
  *"/.par"*|*"/sub/.p"*) _fail "mount recorded a synthetic .parent branch: $(cat "$T1/vendor/sub/.be")" ;;
esac

REFS0=$(_refs)

# --- 2. the sub's own commit: wt advances, NO ref moves ---------------------
printf 'sub payload v2 EDITED\n' > "$T1/vendor/sub/lib.c"
( cd "$T1/vendor/sub" && "$JABC" put lib.c && "$JABC" post '#s2' ) \
    >"$WORK/s2.out" 2>"$WORK/s2.err" || _fail "sub own commit failed: $(cat "$WORK/s2.err")"
S1=$(sc_subtip "$T1/vendor/sub"); sc_is40 "$S1" "sub tip1"
[ "$S1" != "$SUBTIP0" ] || _fail "sub commit did not advance the sub wt"
[ "$(sc_gitlink_pin "$T1" "$SUBPATH")" = "$SUBTIP0" ] \
    || _fail "sub own commit spuriously bumped the parent gitlink"
[ "$(_refs)" = "$REFS0" ] || _fail "sub own commit MOVED a ref (must move none)"

# --- 3. the parent's post: gitlink bump + child re-attach, still no ref -----
( cd "$T1" && "$JABC" post '#absorb sub' ) >"$WORK/pp.out" 2>"$WORK/pp.err" \
    || _fail "parent absorb post failed: $(cat "$WORK/pp.err")"
[ "$(sc_gitlink_pin "$T1" "$SUBPATH")" = "$S1" ] \
    || _fail "parent post did not bump the gitlink to $S1"
ANCH=$(od -An -c "$T1/vendor/sub/.be" | tr -d ' \n')
case "$ANCH" in
  *"///vendor/sub#$S1"*) ;;
  *) _fail "parent post did not re-attach the child at ///vendor/sub#$S1: $(cat "$T1/vendor/sub/.be")" ;;
esac
[ "$(_refs)" = "$REFS0" ] || _fail "parent post wrote a ref (pin rides the wtlog URI, not refs)"

pass
