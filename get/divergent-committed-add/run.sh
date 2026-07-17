#!/bin/sh
# test/get/divergent-committed-add — GET-048 (the work/ABC-016 `del
# test/EXIT.c` incident) × GET.mkd intro (edited 2026-07-17): the local
# commit ADDS z.txt, the target branch NEVER had it, then a divergent get.
# The checkout resets to the target (z.txt leaves the wt — it lives on in
# the CL commit), but the file must NEVER be reported as an upstream `del`:
# the target never knew it, so a `del z.txt` row is a lie under any reading
# (with base = local head, "target lacks the file" mis-reads as an upstream
# deletion).  The commit — and the added blob — must survive in the store.
# RED at GET-048 filing: the reconcile diffs local-head-tree vs target-tree
# and brands the ours-only z.txt `del z.txt` in the get hunk.
. "$(dirname "$0")/../../lib/getrepro.sh"

# Common base c1 (no z.txt anywhere upstream).
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt
"$BE" post 'c1' >/dev/null 2>&1
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"

# Local branch L: COMMIT the ADD of z.txt (published, DIS-076).
gr_jclone "$SRC" "$WORK/jL"
cd "$WORK/jL"
printf 'Z\n' > z.txt
"$JABC" put z.txt >/dev/null 2>&1 || _fail "put z.txt failed"
"$JABC" post '?L' '#l1' >/dev/null 2>&1 || _fail "post ?L failed"
"$JABC" post '?L' >/dev/null 2>&1 || _fail "publish ?L failed"
CL=$(gr_tip_sha "$WORK/jL")

# Target branch U: a.txt A->A2 off the SAME c1 — diverged, z.txt-less.
gr_jclone "$SRC" "$WORK/jU"
cd "$WORK/jU"
printf 'A2\n' > a.txt
"$JABC" put a.txt >/dev/null 2>&1 || _fail "put a.txt failed"
"$JABC" post '?U' '#u1' >/dev/null 2>&1 || _fail "post ?U failed"
"$JABC" post '?U' >/dev/null 2>&1 || _fail "publish ?U failed"
CU=$(gr_tip_sha "$WORK/jU")
[ -n "$CL" ] && [ -n "$CU" ] && [ "$CL" != "$CU" ] || _fail "L/U fork setup"

# The divergent get over a CLEAN tree holding the committed add.
rc=$(gr_jget "$WORK/jL" '?U')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?U exit=$rc"; }

# 1. the checkout IS the target tree: z.txt left the wt, a.txt is A2.
[ ! -e "$WORK/jL/z.txt" ] || _fail "reset left z.txt (target never had it)"
gr_file_is "$WORK/jL/a.txt" "A2"

# 2. BRO-030 quad default: z.txt never enters the report (target never had it,
#    all-same) and a.txt resets all-same too, so the report is SILENT.
if grep -qE 'z\.txt' "$WORK/last.out"; then
    echo "--- get out ---"; cat "$WORK/last.out"
    _fail "committed-only add surfaced in the quad report (target never had z.txt)"
fi
if grep -qE '(\.txt$|(^| )(post|mrg|con|upd|new|del) )' "$WORK/last.out"; then
    echo "--- get out ---"; cat "$WORK/last.out"
    _fail "divergent reset emitted rows (quad default: report is silent)"
fi

# 3. status clean after — the reset is total, no phantom pending rows.
#    BRO-030 quad default: a dirty file row is `<date7> <quad4> <path>`.
( cd "$WORK/jL" && "$JABC" status ) > "$WORK/st.out" 2>&1 || true
if grep -qE '^.{8}[.xovXOV!]{4} ' "$WORK/st.out"; then
    echo "--- status ---"; cat "$WORK/st.out"
    _fail "divergent reset left pending rows in status"
fi

# 4. the commit — and z.txt's bytes — survive IN THE STORE: the old head
#    resolves and its diff still carries the +Z add (manual-recovery route).
( cd "$WORK/jL" && "$JABC" commit "?$CL" ) > "$WORK/cl.out" 2>&1 \
    || { cat "$WORK/cl.out"; _fail "old head ?$CL no longer resolvable"; }
grep -q "commit $CL" "$WORK/cl.out" \
    || { cat "$WORK/cl.out"; _fail "commit view lacks the CL head"; }
grep -q '^+Z$' "$WORK/cl.out" \
    || { cat "$WORK/cl.out"; _fail "the committed z.txt add is gone from the store"; }

pass
