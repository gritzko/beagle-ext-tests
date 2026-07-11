#!/bin/sh
# test/status/subtree — STATUS-006: `jab status <dir>` and bare `jab status` run
# from a subdir cwd must scope to that subtree, NOT silently degrade to the WHOLE
# wt.  A plain (non-submodule) dir arg used to CLIMB to the top repo anchor and
# emit every row; a subdir cwd was ignored entirely.  RED before the fix (both
# show other/'s row too); GREEN after (only the scoped dir's rows).  Seed via $BE
# (fixture), assert via $JABC — the test/status/root recipe.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/status/subtree
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "status/subtree: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "status/subtree: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=subtree
WORK="$TMP/$$/status/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `jsrc -> <be/>` shard symlink so bareword `jab status`
# resolves the extension via jab's upward be/-scan from the scratch cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [status/$NAME] $*" >&2; exit 1; }
have() { grep -qE "$2" "$1" || { echo "--- $1 ---"; cat -A "$1" >&2; _fail "$3 (expected /$2/)"; }; }
miss() { grep -qE "$2" "$1" && { echo "--- $1 ---"; cat -A "$1" >&2; _fail "$3 (unexpected /$2/)"; } || true; }

# A committed baseline, then dirty a file in TWO different dirs (wiki/ + other/).
WT="$WORK/wt"; mkdir -p "$WT/.be"
cd "$WT"
mkdir -p wiki other
printf 'A\n' > wiki/a.txt
printf 'B\n' > other/b.txt
"$BE" post 'base' >/dev/null 2>&1 || _fail "could not seed the baseline"
printf 'A2\n' > wiki/a.txt
printf 'B2\n' > other/b.txt

# --- leg (a): `status wiki` (explicit dir arg) shows ONLY wiki/'s row ---------
( cd "$WT" && "$JABC" status wiki --plain ) >"$WORK/arg" 2>"$WORK/arg.err" \
    || _fail "status wiki failed: $(cat "$WORK/arg.err")"
have "$WORK/arg" 'mod wiki/a\.txt' "status wiki: the wiki/ edit present"
miss "$WORK/arg" 'other/b\.txt'    "status wiki: the other/ edit must be absent"

# --- leg (b): bare `status` from the wiki/ cwd scopes to wiki/ ----------------
( cd "$WT/wiki" && "$JABC" status --plain ) >"$WORK/bare" 2>"$WORK/bare.err" \
    || _fail "bare status from wiki/ failed: $(cat "$WORK/bare.err")"
have "$WORK/bare" 'mod wiki/a\.txt' "bare status @wiki: the wiki/ edit present"
miss "$WORK/bare" 'other/b\.txt'    "bare status @wiki: the other/ edit must be absent"

# --- no whole-wt degrade: a clean subtree emits NO dirty row ------------------
mkdir -p clean; printf 'C\n' > clean/c.txt
( cd "$WT" && "$JABC" status clean --plain ) >"$WORK/clean" 2>/dev/null || true
miss "$WORK/clean" 'mod (wiki|other)/' "status clean: no whole-wt degrade (clean subtree)"

# --- bare `status` from the wt ROOT stays whole-wt (unchanged) ----------------
( cd "$WT" && "$JABC" status --plain ) >"$WORK/root" 2>/dev/null || true
have "$WORK/root" 'mod wiki/a\.txt'  "root status: wiki/ present (whole-wt)"
have "$WORK/root" 'mod other/b\.txt' "root status: other/ present (whole-wt)"

echo "PASS [status/$NAME]"
