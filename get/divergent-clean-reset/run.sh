#!/bin/sh
# test/get/divergent-clean-reset — GET-048 × GET.mkd intro+§4 (edited
# 2026-07-17): get "never changes history — only resets the worktree to a
# chosen version"; ONLY uncommitted changes are carried by weave.  So a
# DIVERGENT get over a CLEAN tree is a PLAIN RESET to the target: the locally
# COMMITTED delta must NOT be replayed as pending mods (no mrg rows, status
# clean after), tracking re-points to the target, and the abandoned local
# head stays resolvable by hash (`jab commit '?<sha>'` — the explicit
# `patch '#<sha>'` route recovers it).
# RED at GET-048 filing: leaf() judges dirty against the MERGE-BASE blob
# (basePaths), so the committed a.txt delta reads dirty → `mrg a.txt`, the wt
# keeps A2, and status reports `mod a.txt` on what should be a clean reset.
. "$(dirname "$0")/../../lib/getrepro.sh"

# Common base c1 in a shared local store (a local jclone REDIRECTS to the
# source store, so both worktrees' published branches meet in SRC/.be).
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt; printf 'B\n' > b.txt
"$BE" post 'c1' >/dev/null 2>&1
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"

# Local branch L: commit a.txt A->A2, publish (DIS-076: explicit ref post).
gr_jclone "$SRC" "$WORK/jL"
cd "$WORK/jL"
printf 'A2\n' > a.txt
"$JABC" put a.txt >/dev/null 2>&1 || _fail "put a.txt failed"
"$JABC" post '?L' '#l1' >/dev/null 2>&1 || _fail "post ?L failed"
"$JABC" post '?L' >/dev/null 2>&1 || _fail "publish ?L failed"
CL=$(gr_tip_sha "$WORK/jL")

# Target branch U: b.txt B->B2 off the SAME c1 — a genuine DAG fork.
gr_jclone "$SRC" "$WORK/jU"
cd "$WORK/jU"
printf 'B2\n' > b.txt
"$JABC" put b.txt >/dev/null 2>&1 || _fail "put b.txt failed"
"$JABC" post '?U' '#u1' >/dev/null 2>&1 || _fail "post ?U failed"
"$JABC" post '?U' >/dev/null 2>&1 || _fail "publish ?U failed"
CU=$(gr_tip_sha "$WORK/jU")
[ -n "$CL" ] && [ -n "$CU" ] && [ "$CL" != "$CU" ] || _fail "L/U fork setup"

# The divergent get: wt CLEAN at CL, target ?U.  Spec: plain reset.
rc=$(gr_jget "$WORK/jL" '?U')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?U exit=$rc"; }

# 1. the checkout IS the target tree: the committed A2 delta is GONE from the
#    wt (it lives on in the CL commit), the target's B2 landed.
gr_file_is "$WORK/jL/a.txt" "A"
gr_file_is "$WORK/jL/b.txt" "B2"

# 2. BRO-030 quad default: a clean divergent reset is SILENT — a.txt/b.txt reset
#    to the target (all-same, omitted), track==base (no commit divergence row).
if grep -qE '(\.txt$|(^| )(post|mrg|con|upd|new|del) )' "$WORK/last.out"; then
    echo "--- get out ---"; cat "$WORK/last.out"
    _fail "clean divergent reset emitted rows (quad default: report is silent)"
fi

# 3. status is CLEAN after — no phantom pending rows of the committed delta.
#    BRO-030 quad default: a dirty file row is `<date7> <quad4> <path>`.
( cd "$WORK/jL" && "$JABC" status ) > "$WORK/st.out" 2>&1 || true
if grep -qE '^.{8}[.xovXOV!]{4} ' "$WORK/st.out"; then
    echo "--- status ---"; cat "$WORK/st.out"
    _fail "reset left phantom `mod` rows (committed delta replayed as dirty)"
fi

# 4. tracking re-pointed: the wtlog records `get ?U#<target tip>`.
gr_wtlog_has "$WORK/jL" "get\?U#$CU"

# 5. history untouched: the abandoned local head resolves by hash.
( cd "$WORK/jL" && "$JABC" commit "?$CL" ) > "$WORK/cl.out" 2>&1 \
    || { cat "$WORK/cl.out"; _fail "old head ?$CL no longer resolvable"; }
grep -q "commit $CL" "$WORK/cl.out" \
    || { cat "$WORK/cl.out"; _fail "commit view lacks the CL head"; }

pass
