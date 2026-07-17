#!/bin/sh
# test/status/track — STATUS-009: status must understand the POST-026 track/base
# split.  A wt's LAST `get` record is `<track>#<base>`: the fragment is the BASE
# commit, EVERYTHING ELSE the TRACK (branch, parent pin, worktree, remote).  A
# mounted sub tracks its parent gitlink pin by a `//…` URI (submount.trackUri) —
# attachedBranch() only knew query-shaped branch names, so the sub read as trunk:
# RED before the fix (summary `?\t2 ok`, no track, no divergence vs the pin);
# GREEN after (summary `<track>#<base8>\t…`, ahead/behind vs the resolve_hash()-
# resolved track tip).  Query-shaped tracks (trunk `?`, `?feat`) and the DIS-075
# bare-`#sha` detached form keep their old labels — pinned here too.
. "$(dirname "$0")/../../sub/lib/subcase.sh"

sc_build_parent

T1="$WORK/get1"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { echo "--- get1 err ---"; cat "$WORK/last.err"; _fail "clone exit $_rc"; }
SUBWT="$T1/vendor/sub"
[ -f "$SUBWT/lib.c" ] || _fail "get1: sub not mounted/checked out"

# The RECORDED track + base: the sub's last `get` row carrying a `#fragment`
# (the DIS-072 parent-pin URI).  Read straight off the ulog text — the test
# must not trust the reader under test.
ROW=$(awk -F'\t' '$2=="get" && $3 ~ /#/ {last=$3} END{print last}' "$SUBWT/.be")
TRACK=${ROW%#*}
BASE=${ROW##*#}
case "$TRACK" in //*) ;; *) _fail "fixture: sub track is not a // URI: [$ROW]" ;; esac
sc_is40 "$BASE" "recorded base"
BASE8=$(printf '%s' "$BASE" | cut -c1-8)

# ---- leg 1: a URI-shaped track shows AS RECORDED + the 8-hex base hashlet ----
( cd "$SUBWT" && "$JABC" status --plain ) >"$WORK/st1.out" 2>"$WORK/st1.err" \
    || { cat "$WORK/st1.err"; _fail "status in the sub failed"; }
grep -qF "$TRACK#$BASE8	" "$WORK/st1.out" || {
    echo "--- sub status ---"; cat "$WORK/st1.out"
    _fail "summary lacks the tracked URI + base hashlet [$TRACK#$BASE8]"
}
grep -q '^?	' "$WORK/st1.out" && {
    echo "--- sub status ---"; cat "$WORK/st1.out"
    _fail "URI-tracked sub still labelled trunk \`?\`"
}
# freshly mounted: cur == the pin, so no (behind/ahead) note.
grep -q '(behind\|(ahead' "$WORK/st1.out" \
    && _fail "fresh mount reports divergence: $(cat "$WORK/st1.out")"

# ---- leg 2: divergence is cur vs the TRACK's resolved tip (the parent pin) ---
( cd "$SUBWT" && printf 'sub payload v2 AHEAD\n' > lib.c \
    && "$JABC" put lib.c && "$JABC" post '#sub ahead' ) >/dev/null 2>&1 \
    || _fail "sub: post ahead failed"
NEWTIP=$(sc_subtip "$SUBWT"); sc_is40 "$NEWTIP" "sub tip (ahead)"
[ "$NEWTIP" != "$BASE" ] || _fail "fixture: the ahead post did not move cur"
NEW8=$(printf '%s' "$NEWTIP" | cut -c1-8)
( cd "$SUBWT" && "$JABC" status --plain ) >"$WORK/st2.out" 2>"$WORK/st2.err" \
    || { cat "$WORK/st2.err"; _fail "status (ahead) in the sub failed"; }
# the track is unchanged; the BASE moved with the post (last fragment-bearing row).
grep -qF "$TRACK#$NEW8	" "$WORK/st2.out" || {
    echo "--- sub status (ahead) ---"; cat "$WORK/st2.out"
    _fail "summary lacks the track + POSTED base [$TRACK#$NEW8]"
}
# ahead exactly 1 vs the pin — only true if the divergence ref IS the track's
# resolved tip (the parent gitlink pin), not trunk/nothing.
grep -qF "(ahead 1)" "$WORK/st2.out" || {
    echo "--- sub status (ahead) ---"; cat "$WORK/st2.out"
    _fail "no (ahead 1) note — divergence not computed vs the track's tip"
}
# BRO-030: the quad-default commit row for a local (base-side) ahead commit is `.o..`.
grep -qE '\.o\.\.[[:space:]]+\?[0-9a-f]{6,40}#sub ahead' "$WORK/st2.out" || {
    echo "--- sub status (ahead) ---"; cat "$WORK/st2.out"
    _fail "no ahead \`.o..\` commit row for the sub-ahead commit"
}

# ---- leg 3: a query-shaped track keeps the old label (trunk `?`) -------------
( cd "$T1" && "$JABC" status --plain --nosub ) >"$WORK/st3.out" 2>/dev/null || true
grep -q '^?	' "$WORK/st3.out" || {
    echo "--- parent status ---"; cat "$WORK/st3.out"
    _fail "trunk-tracked parent lost its bare \`?\` label"
}

# ---- leg 4: DIS-075 detached (bare `#sha` record) labels by the cur tip ------
PARTIP=$(sc_tip "$T1"); sc_is40 "$PARTIP" "parent tip"
( cd "$T1" && "$JABC" get "?$PARTIP" ) >/dev/null 2>&1 || _fail "could not detach parent"
# the clone's `.be` is the wtlog itself (a secondary-wt redirect FILE).
WTLOG="$T1/.be"; [ -f "$WTLOG" ] || WTLOG="$T1/.be/wtlog"
grep -qE "	get	#$PARTIP\$" "$WTLOG" \
    || _fail "detach did not write the DIS-075 \`#<sha>\` record: $(tail -2 "$WTLOG")"
( cd "$T1" && "$JABC" status --plain --nosub ) >"$WORK/st4.out" 2>/dev/null || true
grep -q "^?$PARTIP	" "$WORK/st4.out" || {
    echo "--- detached parent status ---"; cat "$WORK/st4.out"
    _fail "detached wt not labelled by its cur tip \`?<sha>\`"
}

echo "ok   track/base split: URI track + base hashlet + divergence vs the pin"
pass
