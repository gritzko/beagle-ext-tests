#!/bin/sh
# test/cat/links — BRO-006: be/views/cat/cat.js (the syntax-highlight VIEW)
# must emit `U` click-targets on its name/symbol (N/C) tokens so the bro
# pager's left-click consumer (views/bro/pager.js `_uriAt`) can navigate.
# The C cat/file-view (bro/BRO.c) emits NO per-token `U`; the only symbol nav
# it does is the right-click `grep:#<word>` (BRO.c:2968) — this ports THAT to
# a left-click `U` -> `grep:#<symbol>`.  Driven as a jab unit script (the
# parity oracle does not apply: there is no native `U`-in-cat to diff against).
# RED pre-fix (no `U` tokens), GREEN after.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/cat/links
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
_BIN=${BIN:-$( [ -n "$BE" ] && dirname "$BE" || echo "" )}
JABC=${JABC:-$_BIN/jab}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "cat/links: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "cat/links: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
: "${TMP:=/tmp}"; export TMP

"$JABC" "$_CASE/links.js"
