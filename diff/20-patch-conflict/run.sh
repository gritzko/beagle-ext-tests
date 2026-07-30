#!/bin/sh
#  DIFF-016 (DIS-080): an OVERLAP — a run where both the patch-in and the local
#  edit touched the same anchor — renders YELLOW, not the two families side by
#  side.  With fences retired (PATCH-025) the diff view is where a conflict is
#  seen, so this is the load-bearing case.
#
#       T0 ── (trunk, ours) : committed f.txt = a/b/c   ← the base
#         \                   wt on disk (uncommitted) : a/Y/c   ← dirty line 2
#          F1  (?feat, theirs): committed f.txt = a/X/c          ← SAME line
#
#  `patch ?feat` conflicts: the wt gets the RGA live reading (`a`,`XY`,`c`, NO
#  markers) and a durable `con f.txt` row.  The diff then shows ONE run holding
#  X (theirs) and Y (ours), so the whole run washes yellow — no salad, no blue.
#
#  The yellow is derived from the WEAVE (a run carrying both provenances, the
#  same membership test `weave.mergedLive` uses), and CROSS-CHECKED here against
#  the row-based [/todo/ULOG/ULOG-004] accessor via `status`'s `con` tally.
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
cq  227 "conflict: the overlapping run washes yellow"
cqn 157 "conflict: the run is NOT local salad"
cqn 117 "conflict: the run is NOT patched-in blue"
cqn 215 "conflict: the run is NOT patched-in orange"

pass
