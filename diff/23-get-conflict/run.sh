#!/bin/sh
#  DIFF-020 (DIS-080): a conflict produced by a MERGE-GET renders with the same
#  provenance axis a patch-conflict does.  [/todo/DIFF/DIFF-016] gated the whole
#  EXPECTED reading on PATCH rows, and a merge-get writes NONE — so the woven
#  both-sides bytes used to diff as an ordinary local edit (salad/salmon only).
#
#       T0 ── (trunk, ours) : committed f.txt = a/b/c, g.txt = 1..5  ← the base
#         \                   wt on disk (uncommitted) : the OURS edits
#          F1  (?feat, theirs): f.txt = a/X/c, g.txt has T after 3
#
#  `get ?#F1` weaves both sides (NO markers) and appends a `con` row per path.
#  After it curTip IS THEIRS, so the pointers the EXPECTED reading needs are the
#  con row's ORIGINS (wtlog.conflictOrigins()): base = the tip pinned before the
#  barrier get, theirs = the barrier get's own sha.  The con path's diff FROM is
#  that PRE-merge base (ruling gritzko 2026-08-03) — against curTip the theirs
#  axis is invisible, because curTip IS theirs.
#
#  ONE patch/conflict mode, 4 provenance washes: ours in/rm salad/salmon, theirs
#  in/rm pale blue/orange.  Yellow (DIFF-016's 229/227) is RETIRED.
#
#  TWO weave shapes ([/wiki/Dirty]):
#   -  g.txt: two insertions sharing ONE anchor (+ a local removal elsewhere) —
#      the tokens stay distinct, so the run INTERLEAVES blue and green.
#   -  f.txt: both sides rewrote the SAME line, so the merged bytes re-tokenise
#      as one glued word `XY` — one local token; the theirs axis survives as the
#      pale-orange removal of the base line.
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt g)
cd "$W"

_jab() { rm -f .be/*/*.keeper.idx 2>/dev/null; "$BE" "$@" >/dev/null 2>&1; }
_tip() { "$JABC" refs 2>/dev/null | sed -n 's/^cur: *//p'; }
cq()  { grep -q "48;5;$1" "$WORK/j.color" || _fail "$2 (expected 256-bg $1)"; }
cqn() { if grep -q "48;5;$1" "$WORK/j.color"; then _fail "$2 (unexpected 256-bg $1)"; fi; }

printf 'a\nb\nc\n' > f.txt
printf '1\n2\n3\n4\n5\n' > g.txt
_jab post 't0'
BOOT=$(_tip)
_jab put '?feat'
_jab get '?feat'
printf 'a\nX\nc\n' > f.txt          # theirs: line 2 = X
printf '1\n2\n3\nT\n4\n5\n' > g.txt # theirs: T inserted after 3
_jab put f.txt g.txt
_jab post 'f1'
F1=$(_tip)
_jab get "?#$BOOT"                  # back to t0 — THE PRE-MERGE BASE
grep -q '^b$' f.txt || _fail "fixture: base wt should carry line 2 = b"

printf 'a\nY\nc\n' > f.txt          # ours: the SAME line 2, DIRTY/uncommitted
printf '1\n2\n3\nO\n4\n' > g.txt    # ours: O at the SAME anchor, and 5 removed
#  POST-032: a weave conflict is a NORMAL merge outcome — get warns, exit 0.
"$JABC" get "?#$F1" >"$WORK/get.out" 2>"$WORK/get.err" || true
grep -q 'merged with conflicts' "$WORK/get.err" "$WORK/get.out" \
    || { cat "$WORK/get.err"; _fail "get: no conflict report" ; }
if grep -q '<<<<' f.txt; then _fail "DIS-080: conflict bytes must carry NO fences"; fi
grep -q 'X' f.txt && grep -q 'Y' f.txt || _fail "fixture: f.txt lost a side"
grep -q '^T$' g.txt && grep -q '^O$' g.txt || _fail "fixture: g.txt lost a side"

#  ULOG-004 cross-check: the row accessor names BOTH paths as live conflicts.
"$JABC" status --plain >"$WORK/st.out" 2>&1 || true
grep -q '2 con' "$WORK/st.out" \
    || { cat "$WORK/st.out"; _fail "status: no con tally for the merged paths"; }

#  --- shape 1: two insertions at ONE anchor + a local removal ---------------
diff_eq "get-merge conflict (one anchor)" 'diff:g.txt'
have '^\+T$'  "conflict: the theirs insertion shows against the PRE-merge base"
have '^\+O$'  "conflict: the ours insertion shows"
have '^-5$'   "conflict: a local removal on the same path still shows"
cq  155 "conflict: the theirs token washes lime (blue channel down)"
cq  157 "conflict: the ours token washes salad green"
cq  217 "conflict: the local removal washes salmon"
cqn 227 "conflict: yellow is RETIRED (one patch/conflict mode, 4 washes)"
cqn 229 "conflict: yellow is RETIRED (the pale twin too)"

#  --- shape 2: the same line both sides — the merged bytes re-tokenise glued --
diff_eq "get-merge conflict (same line)" 'diff:f.txt'
have '^\+XY$' "conflict: the merged run shows as ONE addition"
have '^-b$'   "conflict: the FROM side is the PRE-merge base (line 2 = b)"
cq  215 "conflict: the base line THEIRS removed washes pale orange"
cqn 227 "conflict: yellow is RETIRED"

#  DIFF-016's no-fallback ruling: provenance is a COLOUR distinction only — the
#  --plain body carries no provenance marker of any kind.
miss 'blue|orange|theirs|conflict|48;5;|\[m' "plain: no provenance in --plain"

pass
