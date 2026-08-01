#!/bin/sh
# test/get/line-backward — GET-053: a FAST-BACKWARD target is ON cur's line,
# so it stays a BARE form (`get '#~1'`, a backward `?<sha>` detach).  The
# deciding axis is TARGET vs BASE in both directions, so the backward cells
# read INVERTED against the base column (GET-053 Design decisions 3-4):
#   base `.` → `T.` no-op        (s.txt untouched)
#   base `v` → `Tv` theirs       (a.txt A2 -> A)
#   base `o` → `Tx` delete       (n.txt was CREATED after the target)
#   base `x` → `To` restore      (k.txt was DELETED after the target)
# Same 13 cells, same verdicts — no second table.
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt          # the `v` cell
printf 'S\n' > s.txt          # the `.` cell
printf 'K\n' > k.txt          # the `x` cell (deleted after the target)
"$BE" post 'c1' >/dev/null 2>&1
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"

printf 'A2\n' > a.txt
rm k.txt
printf 'N\n' > n.txt          # the `o` cell (created after the target)
"$BE" put a.txt n.txt >/dev/null 2>&1
"$BE" delete k.txt >/dev/null 2>&1
"$BE" post 'c2' >/dev/null 2>&1
C2=$(gr_tip_sha "$SRC")
[ -n "$C2" ] && [ "$C1" != "$C2" ] || _fail "c2 did not advance"

gr_jclone "$SRC" "$WORK/jT"
gr_file_is "$WORK/jT/a.txt" "A2"
gr_file_is "$WORK/jT/n.txt" "N"
[ ! -e "$WORK/jT/k.txt" ] || _fail "clone @c2 still carries k.txt"

# 1. the fast-BACKWARD rewind is BARE-legal (no bang needed).
rc=$(gr_jget "$WORK/jT" '#~1')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "bare fast-backward refused (exit=$rc)"; }

# 2. the four inverted cells.
gr_file_is "$WORK/jT/s.txt" "S"                       # T. no-op
gr_file_is "$WORK/jT/a.txt" "A"                       # Tv theirs
gr_file_is "$WORK/jT/k.txt" "K"                       # To restore
[ ! -e "$WORK/jT/n.txt" ] || _fail "Tx cell: n.txt created after the target, not deleted"
gr_wtlog_has "$WORK/jT" "$C1"

# 3. status is CLEAN after the walk back — the wt IS the target tree, no
#    phantom dirt from reading the axis the wrong way round.
( cd "$WORK/jT" && "$JABC" status ) > "$WORK/st.out" 2>&1 || true
if grep -qE '^.{8}[.xovXOV!]{4} ' "$WORK/st.out"; then
    echo "--- status ---"; cat "$WORK/st.out"
    _fail "fast-backward left dirty rows behind"
fi

# 4. forward again (fast-forward, bare-legal), then a BACKWARD `?<sha>`
#    detach — also a fast-backward, so also bare-legal.
rc=$(gr_jget "$WORK/jT" "?#$C2")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "fast-forward pin refused (exit=$rc)"; }
gr_file_is "$WORK/jT/a.txt" "A2"

rc=$(gr_jget "$WORK/jT" "?$C1")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "backward ?<sha> detach refused (exit=$rc)"; }
gr_file_is "$WORK/jT/a.txt" "A"
gr_file_is "$WORK/jT/k.txt" "K"
[ ! -e "$WORK/jT/n.txt" ] || _fail "backward detach left n.txt behind"

pass
