#!/bin/sh
# test/status/colors — DIS-057: `be status --color` paints EVERY status bucket
# with the native C hue.  Pure unit test of view/theme.js `verbPaint`/`verbReset`
# (the THEME color-slot table the status row render uses) against a per-bucket
# SGR oracle mirrored from dog/THEME.c + dog/ULOG.c + sniff/SNIFF.exe.c.  No tty,
# no `be`, no commit chain — feed synthetic bucket names and assert the exact slot
# + SGR per bucket.  RED before theme.js maps rmv/pat/cnf to their C families;
# GREEN after.  Registered by the be/test glob as be-js-status-colors (no
# CMakeLists edit), modelled on test/bro/status.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/status/colors
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "status/colors: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/view/theme.js" ] || { echo "status/colors: SKIP — no $BEDIR/view/theme.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "status/colors: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=colors
WORK="$TMP/$$/status/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink so `require("view/theme.js")`
# resolves the extension via jab's upward be/-scan from the worktree cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sf "$BEDIR" "$TMP/$$/be" 2>/dev/null || true

_fail() { echo "FAIL [status/$NAME] $*" >&2; exit 1; }

cd "$WORK"
"$JABC" "$_CASE/check.js" >"$WORK/check.out" 2>&1 \
    || { cat "$WORK/check.out" >&2; _fail "per-bucket colour assertions failed"; }
grep -q "test/status/colors OK" "$WORK/check.out" || { cat "$WORK/check.out" >&2; _fail "check.js did not report OK"; }

echo "PASS [status/$NAME]"
