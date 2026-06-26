#!/bin/sh
# test/bro/status — BRO-008: the bro status URI keeps the scheme for listing/
# query views (`ls:be/#L1`) and the bare cat-style `<path>#L<n>` for file-content
# views (cat/diff/blob).  Pure unit test of view/bro.js `statusURI` — no tty, no
# `be`, no commit chain: feed synthetic hunk URIs and assert the exact status
# string per view.  RED before the keep-scheme set (scheme stripped for ls:),
# GREEN after.  The expected strings are byte-identical to C bro BROStatusURI
# (bro/test/STATUS.c) — the C<->jab parity oracle.  Registered by the be/test
# glob as be-js-bro-status — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/bro/status
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "bro/status: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/view/bro.js" ] || { echo "bro/status: SKIP — no $BEDIR/view/bro.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "bro/status: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=status
WORK="$TMP/$$/bro/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink so `require("view/bro.js")`
# resolves the extension via jab's upward be/-scan from the worktree cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sf "$BEDIR" "$TMP/$$/be" 2>/dev/null || true

_fail() { echo "FAIL [bro/$NAME] $*" >&2; exit 1; }

cd "$WORK"
"$JABC" "$_CASE/check.js" >"$WORK/check.out" 2>&1 \
    || { cat "$WORK/check.out" >&2; _fail "statusURI assertions failed"; }
grep -q "test/bro/status OK" "$WORK/check.out" || { cat "$WORK/check.out" >&2; _fail "check.js did not report OK"; }

echo "PASS [bro/$NAME]"
