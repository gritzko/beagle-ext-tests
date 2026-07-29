#!/bin/sh
#  PATCH-024: an absorbed patch must NOT move the base tree.  Fixture:
#
#       T0 ── (wt pinned here, the base)
#         \
#          F1            ← ?feat: keep.txt line 3 -> THREE
#
#  After `patch ?feat` the wt carries THREE while the BASE commit T0 still
#  carries 3, so `diff` (wt-vs-base) MUST render that line.  RED before the fix:
#  diff took its from-side from wtlog.baselineTip(), which the patch row moved to
#  F1 — from-side == wt bytes, every path sha-skipped, EMPTY output, exit 0.
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

#  Local DAG helpers (the patchcase.sh shapes): the rolling `.keeper.idx` indexes
#  only the LATEST keeper, so drop it per op or the t0 fork point reads MISSING.
_jab() { rm -f .be/*.keeper.idx 2>/dev/null; "$BE" "$@" >/dev/null 2>&1; }
_tip() { "$JABC" refs 2>/dev/null | sed -n 's/^cur: *//p'; }

printf '1\n2\n3\n4\n' > keep.txt
_jab post 't0'                      # bootstrap trunk @ t0 (post alone, auto-adds)
BOOT=$(_tip)
_jab put '?feat'                    # label feat @ t0
_jab get '?feat'
printf '1\n2\nTHREE\n4\n' > keep.txt
_jab put keep.txt
_jab post 'f1'
_jab post '?feat'
_jab get "?#$BOOT"                  # back to t0 — THE BASE
grep -q '^3$' keep.txt || _fail "fixture: base wt should carry line 3"

"$JABC" patch '?feat' >"$WORK/patch.out" 2>"$WORK/patch.err" \
    || _fail "patch ?feat failed: $(cat "$WORK/patch.err")"
grep -q '^THREE$' keep.txt || _fail "fixture: patch did not land THREE in the wt"

#  status is the oracle (wiki/Status.mkd): base column untouched, patch+wt lit.
"$JABC" status --plain >"$WORK/st.out" 2>&1 || true
grep -Eq '\.\.[vV][vV!] +keep\.txt' "$WORK/st.out" \
    || { cat "$WORK/st.out"; _fail "status: no ..vv row for keep.txt"; }

#  THE BUG: bare wt-vs-base diff must render the patched-in line.
diff_jab "wt-vs-base after patch" 'diff:'
have '^\+THREE$'  "bare diff: patched-in THREE is an addition"
have '^-3$'       "bare diff: the base line 3 is removed"

#  path-scoped shape takes the same from-side.
diff_jab "file wt-vs-base after patch" 'diff:keep.txt'
have '^\+THREE$'  "file diff: patched-in THREE is an addition"

pass
