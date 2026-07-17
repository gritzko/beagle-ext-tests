#!/bin/sh
# test/status/subquad — STATUS-014: when `status` recurses into a MOUNTED sub,
# the sub's quad columns derive from the PARENT's pins, not the sub's DIS-072
# self-referential track row.  Fixture: a parent that PINS the sub at SUBTIP1
# (track.c added upstream), cloned, then the sub CHECKOUT rolled BACK to SUBTIP0
# (behind its pin) + a local sub post (ahead) + a sub wt edit — so the recursed
# sub hunk lights the three columns INDEPENDENTLY:
#   track col: `o... track.c`   — track pin SUBTIP1 carries track.c, root/base do not
#   base  col: `.v.. helper.c`  — the sub's own ahead post (`.o..` commit)
#   wt    col: `...v lib.c`      — the sub's uncommitted dirt
# plus the summary spells the parent-mount PIN form `//WT/sub#<basePin8>`.
#
# RED before the fix (the sub's self-ref quads): the recursed sub hunk showed
# ONLY `...v vendor/sub/lib.c` + a detached `?<subcur>  1 wt` summary — no track
# row, no base row, no ahead/behind commit rows, no pin-form label.  GREEN after:
# the track/base columns + both commit rows appear and the label is the pin form.
. "$(dirname "$0")/../../sub/lib/subcase.sh"

sc_build_parent

# ---- upstream: SUBTIP1 ADDS track.c; the parent absorbs it (pin -> SUBTIP1) --
( cd "$SUBSTORE" && printf 'track pin file\n' > track.c \
    && "$JABC" put track.c && "$JABC" post '#sub v2' ) >/dev/null 2>&1 \
    || _fail "sub upstream post (add track.c)"
SUBTIP1=$(sc_tip "$SUBSTORE"); sc_is40 "$SUBTIP1" "sub tip1"
[ "$SUBTIP1" != "$SUBTIP0" ] || _fail "fixture: sub upstream tip did not move"
( cd "$PARSTORE/vendor/sub" && "$JABC" get "file://$SUBSTORE/.be#$SUBTIP1" ) \
    >/dev/null 2>&1 || _fail "advance parent's sub mount to SUBTIP1"
( cd "$PARSTORE" && "$JABC" post '#absorb sub v2' ) >/dev/null 2>&1 \
    || _fail "parent absorb post"
[ "$(sc_gitlink_pin "$PARSTORE" "$SUBPATH")" = "$SUBTIP1" ] \
    || _fail "fixture: parent gitlink not bumped to SUBTIP1"
SUBTIP1_8=$(printf '%s' "$SUBTIP1" | cut -c1-8)

# ---- clone (base = the SUBTIP1 pin), then roll the sub CHECKOUT back to SUBTIP0
T1="$WORK/wt"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { cat "$WORK/last.err"; _fail "clone exit $_rc"; }
SUBWT="$T1/vendor/sub"
[ "$(sc_gitlink_pin "$T1" "$SUBPATH")" = "$SUBTIP1" ] \
    || _fail "clone base pin != SUBTIP1"
( cd "$SUBWT" && "$JABC" get "?$SUBTIP0" ) >"$WORK/roll.out" 2>&1 \
    || { cat "$WORK/roll.out"; _fail "roll sub checkout back to SUBTIP0"; }
[ "$(sc_subtip "$SUBWT")" = "$SUBTIP0" ] || _fail "sub not rolled back to SUBTIP0"
[ -f "$SUBWT/track.c" ] && _fail "fixture: track.c should be gone at SUBTIP0"

# ---- (b) a local sub post (ahead of root): edits helper.c ---------------------
( cd "$SUBWT" && printf 'sub helper AHEAD\n' > helper.c \
    && "$JABC" post '#sub ahead' ) >/dev/null 2>&1 || _fail "sub ahead post"
# ---- (c) sub wt dirt (uncommitted): lib.c -----------------------------------
printf 'sub payload DIRTY\n' > "$SUBWT/lib.c" || _fail "dirty lib.c"

# ---- PARENT status recurses: assert the sub hunk's three columns + label -----
( cd "$T1" && "$JABC" status --plain ) >"$WORK/st.out" 2>"$WORK/st.err" \
    || { cat "$WORK/st.err"; _fail "parent status failed"; }
_dump() { echo "--- parent status ---"; cat "$WORK/st.out"; }

# (a) track column: track.c present only in the track pin (SUBTIP1) -> `o...`
grep -qE '(^|[[:space:]])o\.\.\. vendor/sub/track\.c$' "$WORK/st.out" \
    || { _dump; _fail "no track-column \`o... vendor/sub/track.c\` (RED pre-fix)"; }
# (b) base column: the sub's ahead post touched helper.c -> `.v..`
grep -qE '(^|[[:space:]])\.v\.\. vendor/sub/helper\.c$' "$WORK/st.out" \
    || { _dump; _fail "no base-column \`.v.. vendor/sub/helper.c\` (RED pre-fix)"; }
# (c) wt column: the uncommitted lib.c edit -> `...v`
grep -qE '(^|[[:space:]])\.\.\.v vendor/sub/lib\.c$' "$WORK/st.out" \
    || { _dump; _fail "no wt-column \`...v vendor/sub/lib.c\`"; }
# the ahead post reads a base-side `.o..` commit row (sub off its pin)
grep -qE '\.o\.\. \?[0-9a-f]{6,40}#sub ahead' "$WORK/st.out" \
    || { _dump; _fail "no \`.o..\` ahead commit row (RED pre-fix)"; }
# the behind (track-side) commit — the pin SUBTIP1 the sub does NOT hold -> `o...`
grep -qE '(^|[[:space:]])o\.\.\. \?[0-9a-f]{6,40}#sub v2' "$WORK/st.out" \
    || { _dump; _fail "no \`o...\` behind commit row for the track pin (RED pre-fix)"; }
# the sub summary spells the parent-mount PIN form + the BASE-pin hashlet
grep -qF "///vendor/sub#$SUBTIP1_8	" "$WORK/st.out" \
    || { _dump; _fail "sub summary lacks the pin form ///vendor/sub#$SUBTIP1_8 (RED pre-fix)"; }
# per-column counts + the divergence note
grep -qF '1 track, 1 base, 1 wt' "$WORK/st.out" \
    || { _dump; _fail "sub summary lacks the quad-column counts [1 track, 1 base, 1 wt]"; }
grep -qF '(behind 1, ahead 1)' "$WORK/st.out" \
    || { _dump; _fail "sub summary lacks the (behind 1, ahead 1) note"; }

echo "ok   recursed sub: pin-derived track/base columns + pin-form label"
pass
