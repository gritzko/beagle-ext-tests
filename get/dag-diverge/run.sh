#!/bin/sh
# test/get/dag-diverge — GET-047 × GET.mkd 3.4: a TRUE commit-DAG divergence —
# branches A and B fork off c1 with DISJOINT line edits to f.txt, the wt sits
# CLEAN on A, `get ?B`.  Spec: "divergent - all non-trivial cases resolved by
# weave merge; if that fails, errs out" — so BOTH sides' edits should land.
# UNREGISTERED (.broken): at fe042740 the get neither weaves nor errs — exit 0
# and the wt is clean-reset to B's tree (ours' committed X1 edit is gone from
# the wt, no markers, no refusal; fanoutWholeTree diffs oldTip vs tip only,
# never the merge base).  MISMATCH evidence for GET-047.
. "$(dirname "$0")/../../lib/getrepro.sh"

# Common base c1: one multi-line file so the branch edits are DISJOINT.
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'l1\nl2\nl3\nl4\nl5\n' > f.txt
"$BE" post 'c1' >/dev/null 2>&1
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"

# Branch A: first-line edit, committed + published (DIS-076: a message-post
# never moves a ref — publish explicitly so ?A / ?B resolve).
gr_jclone "$SRC" "$WORK/jA"
cd "$WORK/jA"
printf 'X1\nl2\nl3\nl4\nl5\n' > f.txt
"$JABC" put f.txt >/dev/null 2>&1 || _fail "put (A) failed"
"$JABC" post '?A' '#a1' >/dev/null 2>&1 || _fail "post ?A failed"
"$JABC" post '?A' >/dev/null 2>&1 || _fail "publish ?A failed"
CA=$(gr_tip_sha "$WORK/jA")

# Branch B: last-line edit off the SAME c1 — a genuine DAG fork.
gr_jclone "$SRC" "$WORK/jB"
cd "$WORK/jB"
printf 'l1\nl2\nl3\nl4\nL5\n' > f.txt
"$JABC" put f.txt >/dev/null 2>&1 || _fail "put (B) failed"
"$JABC" post '?B' '#b1' >/dev/null 2>&1 || _fail "post ?B failed"
"$JABC" post '?B' >/dev/null 2>&1 || _fail "publish ?B failed"
CB=$(gr_tip_sha "$WORK/jB")
[ -n "$CA" ] && [ -n "$CB" ] && [ "$CA" != "$CB" ] || _fail "A/B fork setup"

# The divergent get: wt clean on A, target ?B.  SPEC 3.4: the weave merges
# both sides — X1 AND L5 both land.  FAILS today: f.txt becomes B's tree
# verbatim (l1..l4,L5), the X1 side silently absent from the wt.
rc=$(gr_jget "$WORK/jA" '?B')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?B exit=$rc (refused divergence?)"; }
grep -q '^X1$' "$WORK/jA/f.txt" || { echo "--- f.txt ---"; cat "$WORK/jA/f.txt"; \
    _fail "3.4: ours' X1 edit absent — clean reset to B, no weave"; }
grep -q '^L5$' "$WORK/jA/f.txt" || { echo "--- f.txt ---"; cat "$WORK/jA/f.txt"; \
    _fail "3.4: theirs' L5 edit absent"; }

pass
