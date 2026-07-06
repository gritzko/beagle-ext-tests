#!/bin/sh
# test/status/root — WHY-001: `jab status /` must show the WHOLE-wt status, the
# same as bare `jab status`.  A leading `/` is a wt-ROOT-relative path (the wt
# root), NOT the filesystem root; status.js mis-read it as an absolute FS path and
# handed `/` to be.find, which walks UP for a `.be` anchor and finds none →
# "be.find: no .be worktree anchor from '/'".  RED before the fix (status / errors,
# 0 rows); GREEN after (status / == bare status).  Seed via $BE (fixture), assert
# via $JABC — the test/status/links recipe.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/status/root
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (it LAGS jab); locate jab and
# alias BE=$JABC so legacy `"$BE" post/put` seeds run jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "status/root: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "status/root: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "status/root: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=root
WORK="$TMP/$$/status/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink so bareword `jab status`
# resolves the extension via jab's upward be/-scan from the scratch cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [status/$NAME] $*" >&2; exit 1; }

# A committed baseline + one edited file, so the status view has a real `mod` row.
WT="$WORK/wt"; mkdir -p "$WT/.be"
( cd "$WT" && printf 'A\n' > a.txt && "$BE" post 'base' >/dev/null 2>&1 ) \
    || _fail "could not seed the baseline"
( cd "$WT" && sleep 0.02 && printf 'A2\n' > a.txt ) || _fail "could not dirty the tree"

# bare `status` (the whole-wt view) vs `status /` (the wt ROOT) — both scope the
# ENTIRE wt, so their plain output must be identical.
( cd "$WT" && "$JABC" status   --plain ) >"$WORK/bare" 2>/dev/null || true
( cd "$WT" && "$JABC" status / --plain ) >"$WORK/root" 2>"$WORK/root.err" || true

# 1. `status /` must not raise be.find on '/' (the RED symptom).
if grep -q "no .be worktree anchor" "$WORK/root.err"; then
    echo "--- status / stderr ---"; sed -n '1,3p' "$WORK/root.err" >&2
    _fail "status / raised be.find on '/': a leading / is the wt ROOT, not FS root"
fi
[ -s "$WORK/root" ] || _fail "status / emitted ZERO bytes (should be the wt view)"

# 2. `status /` == bare `status`.  Normalise HH:MM (both runs share the tree state,
# but guard a minute-boundary rollover between the two invocations).
norm() { sed 's/[0-9][0-9]:[0-9][0-9]/TT:TT/g'; }
norm <"$WORK/bare" >"$WORK/bare.n"
norm <"$WORK/root" >"$WORK/root.n"
if ! cmp -s "$WORK/bare.n" "$WORK/root.n"; then
    echo "--- bare status ---"; cat "$WORK/bare" >&2
    echo "--- status / ---";    cat "$WORK/root" >&2
    _fail "status / differs from bare status (should be the whole-wt view)"
fi
echo "ok: status / == bare status (the wt-root scope)"

echo "PASS [status/$NAME]"
