#!/bin/sh
# test/sub/bareunk — PUT-009 RULING (gritzko 2026-07-16): bare `jab put`
# stages ONLY tracked-dirty (`mod`) files — an untracked file is NEVER staged
# by the bare form, neither in the parent nor inside a mounted sub (deletions
# are delete's job; unks stage MANUALLY only).  Guards the fold both ways:
#   1. bare put skips unk at every level (no row in either wtlog);
#   2. the manual form `jab put <sub-interior-path>` stages the unk INSIDE
#      the sub (its OWN wtlog), no parent leak (SUBS-039 delegation).
# TEST-003 FLAGGED: needs the JS-keeper feature — the mounted sub CHILD is
# fetched over the git/keeper WIRE (submount.mount), no keeper-free local path.
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent

T1="$WORK/get1"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { echo "--- get1 err ---"; cat "$WORK/last.err"; _fail "clone exit $_rc"; }
[ -f "$T1/vendor/sub/lib.c" ] || _fail "get1: sub not mounted/checked out"

# untracked files: parent top-level + a NESTED dir deep inside the mounted
# sub (the STATUS-009 live shape); plus a tracked mod that MUST stage.
printf 'parent unk\n' > "$T1/newtop.txt"
mkdir -p "$T1/vendor/sub/status/track"
printf '#!/bin/sh\necho repro\n' > "$T1/vendor/sub/status/track/run.sh"
printf 'int main(void){return 1;}\n' > "$T1/main.c"

( cd "$T1" && "$JABC" put ) >"$WORK/put1.out" 2>"$WORK/put1.err" \
    || { cat "$WORK/put1.err"; _fail "bare put failed"; }

# the mod stages; NEITHER unk gets a row in EITHER wtlog.
grep -qE 'put[[:space:]]+main\.c' "$T1/.be" \
    || _fail "parent mod main.c not staged"
grep -qE 'put[[:space:]]+newtop\.txt' "$T1/.be" \
    && _fail "bare put staged a parent unk: $(cat "$T1/.be")"
grep -qE 'put[[:space:]]+status/track/run\.sh' "$T1/vendor/sub/.be" \
    && _fail "bare put staged a sub unk: $(cat "$T1/vendor/sub/.be")"
echo "ok   1. bare put stages mod only; parent+sub unk skipped"

# manual staging: an explicit sub-interior path delegates INTO the sub.
( cd "$T1" && "$JABC" put vendor/sub/status/track/run.sh ) \
    >"$WORK/put2.out" 2>"$WORK/put2.err" \
    || { cat "$WORK/put2.err"; _fail "manual sub-unk put failed"; }
grep -qE 'put[[:space:]]+status/track/run\.sh' "$T1/vendor/sub/.be" \
    || _fail "manual put did not stage into the sub wtlog: $(cat "$T1/vendor/sub/.be")"
grep -qE 'put[[:space:]]+vendor/sub' "$T1/.be" \
    && _fail "manual sub put leaked into the parent wtlog"
echo "ok   2. manual put stages the sub unk into the sub's own wtlog"

pass
