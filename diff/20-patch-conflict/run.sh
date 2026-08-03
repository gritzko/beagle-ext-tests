#!/bin/sh
#  DIFF-016 (DIS-080): an OVERLAP — a run where both the patch-in and the local
#  edit touched the same anchor.  DIFF-020 (ruling gritzko 2026-08-03) retired
#  yellow: ONE patch/conflict mode, 4 provenance washes, so the overlap renders
#  as the two families MEETING.  With fences retired (PATCH-025) the diff view
#  is where a conflict is seen, so this is the load-bearing case.
#
#       T0 ── (trunk, ours) : committed f.txt = a/b/c   ← the base
#         \                   wt on disk (uncommitted) : a/Y/c   ← dirty line 2
#          F1  (?feat, theirs): committed f.txt = a/X/c          ← SAME line
#
#  `patch ?feat` conflicts: the wt gets the RGA live reading (`a`,`XY`,`c`, NO
#  markers) and a durable `con f.txt` row.  Both sides rewrote the SAME line, so
#  the merged bytes RE-TOKENISE as one glued word `XY` (ours): the theirs axis
#  survives as the pale-orange removal of the base line `b`.  The interleaved
#  blue/green shape is in `23-get-conflict` (distinct tokens, one anchor).
#
#  Provenance is derived from the WEAVE, and CROSS-CHECKED here against the
#  row-based [/todo/ULOG/ULOG-004] accessor via `status`'s `con` tally.
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

_jab() { rm -f .be/*.keeper.idx 2>/dev/null; "$BE" "$@" >/dev/null 2>&1; }
_tip() { "$JABC" refs 2>/dev/null | sed -n 's/^cur: *//p'; }
cq()  { grep -q "48;5;$1" "$WORK/j.color" || _fail "$2 (expected 256-bg $1)"; }
cqn() { if grep -q "48;5;$1" "$WORK/j.color"; then _fail "$2 (unexpected 256-bg $1)"; fi; }

printf 'a\nb\nc\n' > f.txt
_jab post 't0'
BOOT=$(_tip)
_jab put '?feat'
_jab get '?feat'
printf 'a\nX\nc\n' > f.txt          # theirs: line 2 = X
_jab put f.txt
_jab post 'f1'
_jab post '?feat'
_jab get "?#$BOOT"                  # back to t0 — THE BASE (f.txt = a/b/c)
grep -q '^b$' f.txt || _fail "fixture: base wt should carry line 2 = b"

printf 'a\nY\nc\n' > f.txt          # DIRTY, uncommitted, the SAME line 2
_rc=0
"$JABC" patch '?feat' >"$WORK/patch.out" 2>"$WORK/patch.err" || _rc=$?
[ "$_rc" -ne 0 ] || _fail "conflict patch exited 0 — spec: NON-ZERO (PATCHCONFLICT)"
if grep -q '<<<<' f.txt; then _fail "DIS-080: conflict bytes must carry NO fences"; fi
grep -q 'X' f.txt || _fail "fixture: theirs side missing from the merged bytes"
grep -q 'Y' f.txt || _fail "fixture: ours side missing from the merged bytes"

#  ULOG-004 cross-check: the row accessor names f.txt as a live conflict.
"$JABC" status --plain >"$WORK/st.out" 2>&1 || true
grep -q 'con' "$WORK/st.out" \
    || { cat "$WORK/st.out"; _fail "status: no con tally for the conflicted path"; }
grep -Eq '\.\.[vV]! +f\.txt' "$WORK/st.out" \
    || { cat "$WORK/st.out"; _fail "status: no ..v! quad row for f.txt"; }

diff_eq "conflicted overlap" 'diff:f.txt'
have '^\+XY$'   "conflict: plain fallback shows the merged run as ONE addition"
have '^-b$'     "conflict: the base line is a removal"
cq  215 "conflict: the base line THEIRS removed washes pale orange"
cq  157 "conflict: the glued both-sides run washes ours salad"
cqn 227 "conflict: yellow is RETIRED (DIFF-020: one mode, 4 washes)"
cqn 229 "conflict: yellow is RETIRED (the pale twin too)"

pass
