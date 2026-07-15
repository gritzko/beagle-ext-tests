#!/bin/sh
# test/sub/advput — BE-049: pager [put] over a mounted submodule, two arms.
# ARM 1 (context threading): a [put] button fired while the view is NAV'D INTO
# the sub carries a SUB-relative row path; _actSpell must thread the FULL nav
# context (`//WT/vendor/sub`) so the put stages IN the sub (the bug threaded a
# path-less `//host` → the parent tree → PUTNONE, the "adv row :put" report).
# ARM 2 (adv row button): an ADVANCED sub's `adv vendor/sub` status row must
# RENDER a [put] button in the pager TUI (adv was missing from ACT_PUT), and
# the click must stage the parent gitlink bump `put vendor/sub#<tip>` — the
# same row postSubs synthesises — so the next post commits the new pin.
# Plain (non-tty) output must stay button-free.  Real Pager + real driveSpell.
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent                                   # par -> vendor/sub (gitlink)

# The clone is a worktree under `work/`: drive.js names it `//cli` off its cwd basename,
# and URI-016 resolves `//cli` to <project root>/work/cli — so the wt lives under
# $WORK/work and $WORK carries the `.be` anchor the project climb detects.
# (The `par`/`sub` SOURCE stores stay flat at $WORK — they are cloned over
# `file:`, never named `//`.)
WORKD=$(rs_work_root "$WORK")
D="$WORKD/cli"
sc_jget "$D" "file://$PARSTORE/.be" >/dev/null
[ -f "$D/vendor/sub/lib.c" ] || _fail "sub not mounted at $D/vendor/sub"

# ADVANCE the sub: a new sub commit, tip descends the parent's gitlink pin.
( cd "$D/vendor/sub" && printf 'sub payload v2\n' > lib.c \
    && "$JABC" post '#advance sub' ) >/dev/null 2>&1 || _fail "advance sub post"
SUBTIP=$(sc_subtip "$D/vendor/sub"); sc_is40 "$SUBTIP" "advanced sub tip"
PIN0=$(sc_gitlink_pin "$D" "vendor/sub"); sc_is40 "$PIN0" "gitlink pin"
[ "$SUBTIP" != "$PIN0" ] || _fail "sub did not advance (tip == pin)"

# an untracked file INSIDE the sub (arm 1's sub-relative [put] row target).
mkdir -p "$D/vendor/sub/x"
echo "f payload" > "$D/vendor/sub/x/f"

# non-tty parity: the plain status shows the adv row but NO button chrome.
( cd "$D" && "$JABC" status --plain 2>&1 ) | grep -qE 'adv[[:space:]]+vendor/sub' \
    || _fail "no adv row in plain status"
( cd "$D" && "$JABC" status --plain 2>&1 ) | grep -q '\[put\]' \
    && _fail "plain (non-tty) status leaked a [put] button"

# `//NAME` (a worktree at <project root>/work/NAME) names the cloned wt for the
# nav context — the layout above IS that binding; no env var declares it.
cp "$_CASE/drive.js" "$D/drive.js"; ln -sfn "$BEDIR" "$D/jsrc"

cd "$D"
OUT=$("$JABC" ./drive.js 2>&1) || { printf '%s\n' "$OUT"; _fail "drive.js failed"; }
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q "drive OK" || _fail "drive did not complete: $OUT"

# ARM 1 landed: x/f staged in the SUB's own wtlog.
grep -qE 'put[[:space:]]+x/f' "$D/vendor/sub/.be" \
    || _fail "arm1: x/f not staged in the sub wtlog: $(cat "$D/vendor/sub/.be")"

# ARM 2 landed: the gitlink bump row `put vendor/sub#<tip>` in the PARENT wtlog.
grep -qE "put[[:space:]]+vendor/sub#$SUBTIP" "$D/.be" \
    || _fail "arm2: gitlink bump not staged in the parent wtlog: $(tail -4 "$D/.be")"

# The adv row re-buckets to `put` (staged) — and no more adv.
STATUS2=$(cd "$D" && "$JABC" status --plain 2>&1)
printf '%s\n' "$STATUS2" | grep -qE 'put[[:space:]]+vendor/sub' \
    || _fail "adv row did not re-bucket to put: $STATUS2"
printf '%s\n' "$STATUS2" | grep -qE 'adv[[:space:]]+vendor/sub' \
    && _fail "adv row still adv after the bump: $STATUS2"

# END-TO-END: post the parent — fold-decide must commit a NEW 160000 pin equal
# to the sub's CURRENT tip (postSubs recursed arm 1's staged x/f into a fresh
# sub commit, so the pin advances PAST the clicked SUBTIP — that is correct).
( cd "$D" && "$JABC" post '#bump sub pin' ) >/dev/null 2>&1 || _fail "parent post failed"
PIN1=$(sc_gitlink_pin "$D" "vendor/sub"); sc_is40 "$PIN1" "posted pin"
TIP1=$(sc_subtip "$D/vendor/sub")
[ "$PIN1" = "$TIP1" ] || _fail "post did not land the sub tip as the pin: $PIN1 != $TIP1"
[ "$PIN1" != "$PIN0" ] || _fail "pin did not advance past the stale $PIN0"

echo "ok   adv sub row renders [put]; the click stages + posts the gitlink bump"
pass
