#!/bin/sh
#  DIFF-016 (DIS-080): EXPECTED folds ALL in-scope patch rows, so TWO stacked
#  `patch` runs compose in ONE weave and BOTH absorbed changes read as patched
#  in — pale blue/orange, with no local salad anywhere (the wt was never edited
#  by hand).  A local edit added afterwards then lights salad on its own line
#  only, proving the second patch row did not swallow the local axis.
#
#       T0 ── (trunk, ours, the base)
#         \ \
#          \ C2   ?f2 : line 7 = SEVEN
#           C1    ?f1 : line 2 = TWO
#
#  RED before the fix: the two-layer base-vs-wt diff painted all three changes
#  the same salad/salmon.
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

_jab() { rm -f .be/*/*.keeper.idx 2>/dev/null; "$BE" "$@" >/dev/null 2>&1; }
_tip() { "$JABC" refs 2>/dev/null | sed -n 's/^cur: *//p'; }
cq()  { grep -q "48;5;$1" "$WORK/j.color" || _fail "$2 (expected 256-bg $1)"; }
cqn() { if grep -q "48;5;$1" "$WORK/j.color"; then _fail "$2 (unexpected 256-bg $1)"; fi; }

printf '1\n2\n3\n4\n5\n6\n7\n8\n' > s.txt
_jab post 't0'
BOOT=$(_tip)
_jab put '?f1'
_jab get '?f1'
sed 's/^2$/TWO/' s.txt > s.t && mv s.t s.txt
_jab put s.txt
_jab post 'c1'
_jab post '?f1'
_jab get "?#$BOOT"
_jab put '?f2'
_jab get '?f2'
sed 's/^7$/SEVEN/' s.txt > s.t && mv s.t s.txt
_jab put s.txt
_jab post 'c2'
_jab post '?f2'
_jab get "?#$BOOT"                  # back to t0 — THE BASE

"$JABC" patch '?f1' >"$WORK/p1.out" 2>"$WORK/p1.err" \
    || _fail "patch ?f1 failed: $(cat "$WORK/p1.err")"
"$JABC" patch '?f2' >"$WORK/p2.out" 2>"$WORK/p2.err" \
    || _fail "patch ?f2 failed: $(cat "$WORK/p2.err")"
grep -q '^TWO$'   s.txt || _fail "fixture: run 1 did not land TWO"
grep -q '^SEVEN$' s.txt || _fail "fixture: run 2 did not land SEVEN"

#  BOTH stacked absorptions are patched in: blue/orange only, no local salad.
diff_eq "two stacked patch runs" 'diff:s.txt'
have '^\+TWO$'    "stacked: run 1's line"
have '^\+SEVEN$'  "stacked: run 2's line"
cq  155 "stacked: patched-in lime present"
cq  215 "stacked: patched-in orange present"
cqn 157 "stacked: NO local salad (the wt was never hand-edited)"
cqn 217 "stacked: NO local salmon"
cqn 227 "stacked: the two runs touch different anchors — no conflict"

#  a local edit on a THIRD line now lights salad, the patch-ins stay blue.
sed 's/^4$/FOUR/' s.txt > s.t && mv s.t s.txt
diff_eq "stacked + a local edit" 'diff:s.txt'
have '^\+FOUR$'   "stacked+local: the hand edit"
cq  155 "stacked+local: patched-in lime still present"
cq  157 "stacked+local: local salad present"
cqn 227 "stacked+local: distinct anchors — no conflict"

pass
