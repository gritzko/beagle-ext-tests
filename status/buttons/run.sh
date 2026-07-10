#!/bin/sh
# test/status/buttons — BE-041: action buttons on actionable status rows.
# mod/unk rows carry a PAGER-ONLY `[put]` button pair in the HUNK tok32 stream
# (`jab status --tlv`): a VISIBLE label token (painted by the pager, hidden from
# plain) immediately followed by a hidden `O` token whose bytes are the click
# spell `put <wt-relative-path>`; a mis row carries `[del]` + `delete <path>`.
# Paths RAW, no //authority, no pre-resolution (the BE-039 ruling: the VERB
# resolves, rest args stay raw).  Already-staged put/new rows and ok rows carry
# NO button (re-staging is a no-op).  The row's existing hidden `U` nav
# (diff:/cat:, BRO-006/DIS-057) is unchanged.  PLAIN output stays byte-identical
# to the pre-change capture (buttons are pager-only chrome) — dates normalised,
# since the fixture timestamps are live.
# A click on a button must NOT push a result view — the mutation spell runs and
# the CURRENT view refreshes in place (click_refresh.js, the headless Pager).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/status/buttons
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (it LAGS jab); locate jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "status/buttons: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "status/buttons: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "status/buttons: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/status/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall: an empty `.be` FILE above the scratch base stops a cwd-walk
# from escaping to a real $HOME/.be (rs firewall, DIS-024).
: > "$TMP/$$/.be" 2>/dev/null || true
# JS verbs run bareword (`jab status`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# Fixture wt covering every button-relevant bucket:
#   ok.txt   → ok   (committed, untouched — count only, NO row, NO button)
#   mod.txt  → mod  (committed, edited)            → [put] button
#   new.txt  → new  (untracked add, then staged)   → NO button (already staged)
#   unk.txt  → unk  (untracked, unstaged)          → [put] button
#   mis.txt  → mis  (committed, rm'd off disk)     → [del] button
WT="$WORK/wt"; mkdir -p "$WT/.be"
( cd "$WT" && printf 'OK\n' > ok.txt && printf 'M\n' > mod.txt && printf 'S\n' > mis.txt \
    && "$BE" post 'base' >/dev/null 2>&1 ) || _fail "could not seed the baseline"
( cd "$WT" && sleep 0.02 && printf 'M2\n' > mod.txt && printf 'N\n' > new.txt && printf 'U\n' > unk.txt \
    && "$BE" put new.txt >/dev/null 2>&1 \
    && rm -f mis.txt ) || _fail "could not dirty the tree"

# 1. PLAIN parity: byte-identical to the PRE-change output (buttons are pager-
#    only chrome).  The date column is the live clock, so normalise the fixed
#    8-char `<date7> ` prefix on per-file rows; banner + summary compare raw.
( cd "$WT" && "$JABC" status --plain ) >"$WORK/jab.plain" 2>/dev/null || true
[ -s "$WORK/jab.plain" ] || _fail "jab status --plain emitted ZERO bytes"
sed -E 's/^.{8}([a-z]{3}) /\1 /' "$WORK/jab.plain" >"$WORK/jab.norm"
printf 'status\nnew new.txt\nmod mod.txt\nmis mis.txt\nunk unk.txt\n?\t1 ok, 1 new, 1 mod, 1 mis, 1 unk\n' >"$WORK/plain.golden"
cmp -s "$WORK/jab.norm" "$WORK/plain.golden" || {
    echo "--- jab --plain (date-normalised) ---"; cat -A "$WORK/jab.norm"
    echo "--- pre-change golden ---"; cat -A "$WORK/plain.golden"
    _fail "plain output diverged from the pre-change capture"
}
grep -Fq '[put]' "$WORK/jab.plain" && _fail "plain output leaks the [put] label" || true
grep -Fq '[del]' "$WORK/jab.plain" && _fail "plain output leaks the [del] label" || true
echo "ok: jab status --plain is byte-identical to the pre-change capture"

# 2. Button pair + unchanged U navs in the TLV stream.
( cd "$WT" && "$JABC" status --tlv ) >"$WORK/jab.tlv" 2>/dev/null || true
[ -s "$WORK/jab.tlv" ] || _fail "jab status --tlv emitted ZERO bytes"

# Existing hidden U nav per row — UNCHANGED (DIS-057 rule: base-present → diff,
# base-less → cat).  Order-independent set compare.
cat > "$WORK/expect_u" <<EOF
cat new.txt
diff mod.txt
diff mis.txt
cat unk.txt
EOF
# The O click spells — `put` on the actionable (unk/mod) rows, `delete` on the
# mis row, RAW wt-relative args (BE-039: no //authority, no scheme, no pre-
# resolution).  ok/put/new: none, so a count mismatch catches a stray button.
cat > "$WORK/expect_o" <<EOF
put mod.txt
put unk.txt
delete mis.txt
EOF
"$JABC" "$_CASE/assert_buttons.js" "$WORK/jab.tlv" "$WORK/expect_u" "$WORK/expect_o" \
    || _fail "button pair / U nav assertions failed (see assert above)"
echo "ok: mod/unk rows carry [put]+O, mis carries [del]+O; ok/put/new rows don't; U navs unchanged"

# 3. Click behaviour (headless Pager over the same TLV capture): a button click
#    drives the mutation spell and REFRESHES the current view in place (no
#    result screen, no back-stack push); a filename (U nav) click still pushes.
#    Run from inside the WT so loop.isMutation's be-climb finds the shard.
( cd "$WT" && "$JABC" "$_CASE/click_refresh.js" "$WORK/jab.tlv" ) \
    || _fail "click-refresh assertions failed (see assert above)"
echo "ok: a [put]/[del] click mutates + refreshes in place; a nav click still pushes"

echo "PASS [$NAME]"
