#!/bin/sh
# test/get/divergent-dirty-weave — GET-048 × GET.mkd §4 (edited 2026-07-17):
# on a DIVERGENT get, ONLY uncommitted changes are carried over by weave
# merge.  The wt sits on a local committed delta (a.txt A->A2) PLUS one
# UNCOMMITTED edit (m.txt l1->X1); the target branch forked off the same base
# editing m.txt's LAST line.  Spec: the uncommitted X1 weaves onto the target
# (disjoint 3-way vs CUR), while the COMMITTED A2 delta resets away — it must
# NOT reappear as a pending mod.
# RED at GET-048 filing: the weave base is the MERGE-BASE blob, so the
# committed a.txt delta reads dirty too — `mrg a.txt`, A2 survives the get,
# status shows a phantom `mod a.txt` beside the legit m.txt one.
. "$(dirname "$0")/../../lib/getrepro.sh"

# Common base c1: a.txt (the committed-delta probe) + a multi-line m.txt so
# ours' uncommitted edit and theirs' committed edit hit DISJOINT lines.
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt
printf 'l1\nl2\nl3\nl4\nl5\n' > m.txt
"$BE" post 'c1' >/dev/null 2>&1
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"

# Local branch L: COMMIT a.txt A->A2 (published, DIS-076).
gr_jclone "$SRC" "$WORK/jL"
cd "$WORK/jL"
printf 'A2\n' > a.txt
"$JABC" put a.txt >/dev/null 2>&1 || _fail "put a.txt failed"
"$JABC" post '?L' '#l1' >/dev/null 2>&1 || _fail "post ?L failed"
"$JABC" post '?L' >/dev/null 2>&1 || _fail "publish ?L failed"
CL=$(gr_tip_sha "$WORK/jL")

# Target branch U: m.txt last line l5->L5 off the SAME c1.
gr_jclone "$SRC" "$WORK/jU"
cd "$WORK/jU"
printf 'l1\nl2\nl3\nl4\nL5\n' > m.txt
"$JABC" put m.txt >/dev/null 2>&1 || _fail "put m.txt failed"
"$JABC" post '?U' '#u1' >/dev/null 2>&1 || _fail "post ?U failed"
"$JABC" post '?U' >/dev/null 2>&1 || _fail "publish ?U failed"
CU=$(gr_tip_sha "$WORK/jU")
[ -n "$CL" ] && [ -n "$CU" ] && [ "$CL" != "$CU" ] || _fail "L/U fork setup"

# The UNCOMMITTED edit in jL: m.txt first line l1->X1 (disjoint from theirs).
printf 'X1\nl2\nl3\nl4\nl5\n' > "$WORK/jL/m.txt"

# The divergent get: committed A2 + uncommitted X1, target ?U.
rc=$(gr_jget "$WORK/jL" '?U')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?U exit=$rc"; }

# 1. the UNCOMMITTED edit weaved onto the target: X1 AND L5 both in m.txt.
gr_file_is "$WORK/jL/m.txt" "X1
l2
l3
l4
L5"

# 2. the COMMITTED delta did NOT survive the reset: a.txt is the target's A.
gr_file_is "$WORK/jL/a.txt" "A"

# 3. BRO-030 quad default: the uncommitted m.txt weave is the wt-advanced quad
#    `...v`; the committed a.txt delta reset to all-same, so a.txt has NO row.
grep -qF '...v m.txt' "$WORK/last.out" || { echo "--- get out ---"; \
    cat "$WORK/last.out"; _fail "uncommitted m.txt weave not the wt-advanced quad (...v)"; }
if grep -qE ' a\.txt$' "$WORK/last.out"; then
    echo "--- get out ---"; cat "$WORK/last.out"
    _fail "COMMITTED a.txt delta reappeared as a quad row"
fi
# BRO-030: no legacy checkout vocabulary survives the quad-default flip.
if grep -qE '(^| )(mrg|con|upd|new|del) ' "$WORK/last.out"; then
    echo "--- get out ---"; cat "$WORK/last.out"
    _fail "legacy checkout rows leaked into the quad-default report"
fi

# 4. status: BRO-030 quad default — the weaved m.txt reads `...v` (a real pending
#    edit); a.txt does NOT (its committed delta is not replayed as dirty).
( cd "$WORK/jL" && "$JABC" status ) > "$WORK/st.out" 2>&1 || true
grep -qE '\.\.\.v m\.txt' "$WORK/st.out" || { echo "--- status ---"; \
    cat "$WORK/st.out"; _fail "weaved m.txt edit not pending after get"; }
if grep -qE '\.\.\.v a\.txt' "$WORK/st.out"; then
    echo "--- status ---"; cat "$WORK/st.out"
    _fail "committed a.txt delta replayed as a phantom pending mod"
fi

pass
