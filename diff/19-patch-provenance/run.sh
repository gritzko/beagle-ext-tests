#!/bin/sh
#  DIFF-016 (DIS-080): the diff colours a changed token by WEAVE PROVENANCE, not
#  by "changed vs base".  EXPECTED = base ⊕ the in-scope patch-ins (theirs, NO wt
#  layer); a token EXPECTED owns is PATCHED IN and washes lime (insert) /
#  pale orange (remove), a wt-vs-EXPECTED token is a LOCAL edit and keeps the
#  salad/salmon green/red.  Three files, one wt:
#
#       loc.txt  local edit only          → salad 157 / salmon 217, NO blue
#       pat.txt  patched in only          → blue 117 / orange 215, NO salad
#       mix.txt  patched in + local edit  → BOTH families, on different lines
#
#  RED before the fix: every changed token washed salad/salmon — a patched-in
#  line was indistinguishable from a local one.
#
#  Asserts read the SGR PARAMETER digits out of `jab diff --color` (view/theme.js
#  DIFF_WASH); the digits are plain ASCII, so no ANSI-C quoting is needed (dash
#  has no such escape and the posix-sh lint rejects it).
#  `--plain` is asserted UNCHANGED: the C HUNK render ignores tok32 bit 26, so
#  the plain-text fallback stays `+`/`-` for every provenance (DIFF-016 ruling).
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

#  Local DAG helpers (18-patch-base shapes): the rolling `.keeper.idx` indexes
#  only the LATEST keeper, so drop it per op or the fork point reads MISSING.
_jab() { rm -f .be/*/*.keeper.idx 2>/dev/null; "$BE" "$@" >/dev/null 2>&1; }
_tip() { "$JABC" refs 2>/dev/null | sed -n 's/^cur: *//p'; }
#  wash asserts over the last diff_eq's $WORK/j.color.
cq()  { grep -q "48;5;$1" "$WORK/j.color" || _fail "$2 (expected 256-bg $1)"; }
cqn() { if grep -q "48;5;$1" "$WORK/j.color"; then _fail "$2 (unexpected 256-bg $1)"; fi; }

printf '1\n2\n3\n4\n' > loc.txt
printf '1\n2\n3\n4\n' > pat.txt
printf '1\n2\n3\n4\n5\n6\n7\n8\n' > mix.txt
_jab post 't0'                      # bootstrap trunk @ t0 (post alone, auto-adds)
BOOT=$(_tip)
_jab put '?feat'                    # label feat @ t0
_jab get '?feat'
printf '1\n2\nTHREE\n4\n' > pat.txt
printf '1\n2\nTHREE\n4\n5\n6\n7\n8\n' > mix.txt
_jab put pat.txt
_jab put mix.txt
_jab post 'f1'
_jab post '?feat'
_jab get "?#$BOOT"                  # back to t0 — THE BASE
grep -q '^3$' pat.txt || _fail "fixture: base wt should carry line 3"

"$JABC" patch '?feat' >"$WORK/patch.out" 2>"$WORK/patch.err" \
    || _fail "patch ?feat failed: $(cat "$WORK/patch.err")"
grep -q '^THREE$' pat.txt || _fail "fixture: patch did not land THREE in pat.txt"

#  local edits ON TOP: loc.txt (untouched by the patch) and mix.txt line 7.
printf '1\n2\n3\nFOUR\n' > loc.txt
sed 's/^7$/SEVEN/' mix.txt > mix.t && mv mix.t mix.txt

#  1. LOCAL ONLY — salad/salmon, never the patched-in family.
diff_eq "local-only edit" 'diff:loc.txt'
have '^\+FOUR$'   "local: the edit is an addition"
have '^-4$'       "local: the base line is a removal"
cq  157 "local: insert washes salad green"
cq  217 "local: removal washes salmon"
cqn 155 "local: no patched-in lime"
cqn 215 "local: no patched-in orange"
cqn 227 "local: no conflict yellow"

#  2. PATCHED IN ONLY — pale blue/orange, never salad/salmon.
diff_eq "patched-in only" 'diff:pat.txt'
have '^\+THREE$'  "patched: plain fallback keeps + (C HUNK ignores bit 26)"
have '^-3$'       "patched: plain fallback keeps -"
cq  155 "patched: insert washes lime"
cq  215 "patched: removal washes pale orange"
cqn 157 "patched: no local salad"
cqn 217 "patched: no local salmon"
cqn 227 "patched: no conflict yellow"

#  3. MIXED — one file, a patched-in line AND a local line, both families lit.
diff_eq "mixed local + patched-in" 'diff:mix.txt'
have '^\+THREE$'  "mixed: the patched-in line"
have '^\+SEVEN$'  "mixed: the local line"
cq  155 "mixed: patched-in lime present"
cq  215 "mixed: patched-in orange present"
cq  157 "mixed: local salad present"
cq  217 "mixed: local salmon present"
cqn 227 "mixed: separate lines are NOT a conflict"

#  4. the whole-tree walk carries the same provenance (not just the file scope).
diff_eq "whole tree" 'diff:'
cq  155 "tree: patched-in lime present"
cq  157 "tree: local salad present"

pass
