#!/bin/sh
# test/get/dirty — DIS-055 D5 (DATA SAFETY): a dirty baselined file that
# upstream ALSO changed must be 3-WAY MERGED (re-apply the user's uncommitted
# edit onto the new tree), NOT clean-overwritten (silent loss).  GET.mkd intro:
# GET resets the wt "maybe re-applying uncommitted changes".  A genuine conflict
# surfaces loudly (non-zero, markers).  `be get!` discards (clean reset).
. "$(dirname "$0")/../../lib/getrepro.sh"

# Source with TWO commits over a multi-line file so ours/theirs can touch
# DISJOINT line regions (clean 3-way) or OVERLAPPING ones (conflict).
nth_sha() { od -An -c "$1/refs" 2>/dev/null | tr -d ' \n' \
                | grep -oE '#[0-9a-f]{40}' | sed -n "${2}p" | tr -d '#'; }

# ===== case A: disjoint edit -> clean 3-way merge, no silent loss =====
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'l1\nl2\nl3\nl4\nl5\n' > f.txt
"$BE" post 'c1' >/dev/null 2>&1
printf 'l1\nl2\nl3\nl4\nL5\n' > f.txt            # theirs: l5 -> L5 (last line)
"$BE" put f.txt >/dev/null 2>&1
"$BE" post 'c2' >/dev/null 2>&1
C1=$(nth_sha "$SRC/.be/src" 1); C2=$(nth_sha "$SRC/.be/src" 2)
[ -n "$C1" ] && [ -n "$C2" ] && [ "$C1" != "$C2" ] || _fail "two-commit setup"
# Clone, then pin back to c1 so the wt baseline is c1 (f.txt = l1..l5).
gr_jclone "$SRC" "$WORK/A"
gr_jget "$WORK/A" "?#$C1" >/dev/null 2>&1
gr_file_is "$WORK/A/f.txt" "l1
l2
l3
l4
l5"
# OURS: edit the FIRST line (disjoint from theirs' last-line change).
printf 'X1\nl2\nl3\nl4\nl5\n' > "$WORK/A/f.txt"
# GET c2 (theirs changed l5->L5).  3-way merge must keep BOTH X1 and L5.
rc=$(gr_jget "$WORK/A" "?#$C2")
[ "$rc" = 0 ] || { echo "--- err ---"; cat "$WORK/last.err"; \
    echo "--- f.txt ---"; cat "$WORK/A/f.txt"; \
    _fail "D5 clean merge exit=$rc (a disjoint merge must succeed)"; }
grep -q '^X1$' "$WORK/A/f.txt" || { echo "--- f.txt ---"; cat "$WORK/A/f.txt"; \
    _fail "D5: ours' X1 edit was LOST (clean-overwrite, not merged)"; }
grep -q '^L5$' "$WORK/A/f.txt" || { echo "--- f.txt ---"; cat "$WORK/A/f.txt"; \
    _fail "D5: theirs' L5 change was not applied"; }

# ===== case A2: OVERLAPPING edit -> real conflict surfaces LOUDLY =====
gr_jclone "$SRC" "$WORK/A2"
gr_jget "$WORK/A2" "?#$C1" >/dev/null 2>&1     # baseline c1 (l5)
printf 'l1\nl2\nl3\nl4\nMINE5\n' > "$WORK/A2/f.txt"   # ours edits l5 too
rc=$(gr_jget "$WORK/A2" "?#$C2")               # theirs also edits l5 -> conflict
[ "$rc" != 0 ] || _fail "D5: a real conflict must exit NON-ZERO (got $rc)"
grep -q '<<<<' "$WORK/A2/f.txt" || { cat "$WORK/A2/f.txt"; \
    _fail "D5: a conflict must leave merge markers in the wt"; }
grep -q 'MINE5' "$WORK/A2/f.txt" || _fail "D5: ours' side missing from conflict"

# ===== case B: be get! force-discards (clean reset) =====
gr_jclone "$SRC" "$WORK/B"          # at c2 (f.txt l1..l4,L5)
printf 'TOTALLY-DIRTY\n' > "$WORK/B/f.txt"
rc=$(gr_jget "$WORK/B" '!')         # bare bang = force-reset current branch
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get! exit=$rc"; }
gr_file_is "$WORK/B/f.txt" "l1
l2
l3
l4
L5"

pass
