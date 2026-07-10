#!/bin/sh
# test/commit/render — `jab commit "commit:#<sha>"` renders the keeper-metadata
# hunk (COMMIT-003).  The JS view resolves the slot and feeds ONE content HUNK
# with an EMPTY uri; a regression dropped that record in --plain (a hand-built
# tok32 table failed the HUNK reader's drain, so next() skipped the record and
# 0 bytes reached stdout).  Assert the `commit <sha40>` line + the full body are
# present, and that the JS plain output equals native modulo the single trailing
# blank-line separator the HUNK content render appends to EVERY content view.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/commit/render
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (it LAGS jab); locate jab and
# alias BE=$JABC so legacy `"$BE" post/put` seeds run jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "commit: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
# The JS scripts are this be/ tree (be/test -> be/).
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "commit: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "commit: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/commit/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink so bareword `jab commit`
# resolves the extension via jab's upward be/-scan from the worktree cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# One-commit worktree under the isolated scratch base.
WT="$WORK/wt"; mkdir -p "$WT/.be"
( cd "$WT" && printf 'hello\n' > a.txt && "$BE" post 'first commit' >/dev/null 2>&1 ) \
    || _fail "could not seed the one-commit worktree"

# The trunk tip's full 40-hex sha (a resolvable commit object).
SHA=$("$JABC" "$_ROOT/put/tipsha.js" "$WT")
[ -n "$SHA" ] || _fail "could not resolve the trunk tip sha"
case "$SHA" in
    *[!0-9a-f]*|"") _fail "tip sha not 40-hex: '$SHA'" ;;
esac
SHORT=$(printf '%s' "$SHA" | cut -c1-8)

# TEST-003/COMMIT-007: jab-intrinsic — native `be` LAGS jab, so no oracle cmp.
( cd "$WT" && "$JABC" commit "commit:#$SHORT" ) >"$WORK/jab.out" 2>"$WORK/jab.err" \
    || _fail "jab commit failed (stderr: $(cat "$WORK/jab.err"))"

# The bug was ZERO bytes from jab — assert non-empty and the metadata lines.
[ -s "$WORK/jab.out" ] || _fail "jab commit emitted ZERO bytes (COMMIT-003)"
grep -q "^commit $SHA\$"  "$WORK/jab.out" || _fail "missing 'commit <sha40>' line"
grep -q "^tree "          "$WORK/jab.out" || _fail "missing tree header"
grep -q "^author "        "$WORK/jab.out" || _fail "missing author header"
grep -q "^first commit\$" "$WORK/jab.out" || _fail "missing message body"
# COMMIT-007: the author date is HUMAN (ron.date), not the raw git `<epoch> <tz>`.
grep -qE '^author .*[0-9]{10} [+-][0-9]{4}[[:space:]]*$' "$WORK/jab.out" \
    && _fail "author line still shows a raw 10-digit epoch (human date expected)"

echo "PASS [$NAME]"
