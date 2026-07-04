#!/bin/sh
# test/bro/help — BRO-007: the jab pager's `h` key opens a HELP screen.  `h`
# runs the `help:` spell (views/help/help.js, auto-dispatched) → driveSpell →
# pushView, so the help screen is a normal pushed view: scrollable, `-`/BS backs
# out, the status line reads `h: help` (NOT the old `(j/k space g/G : q)` blob).
# Builds a tiny commit chain, captures `jab log: --tlv` (the base view) AND
# `jab help: --tlv` (the help view's real output), then drives the Pager:
#   - feed `h` from the log view → the pushed view's hunk carries BOTH the
#     shortcut rows (j/k, q) AND the URI-scheme rows (commit:, diff:, log:);
#   - feed `-` (back) → returns to the prior (log) view;
#   - assert `_statusLine` renders `h: help` and NOT the old hint blob.
# Registered by the be/test glob as be-js-bro-help — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/bro/help
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "bro/help: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "bro/help: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/views/bro/pager.js" ] || { echo "bro/help: SKIP — no pager.js" >&2; exit 0; }
[ -f "$BEDIR/views/help/help.js" ] || { echo "bro/help: SKIP — no help.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "bro/help: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=help
WORK="$TMP/$$/bro/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink so bareword `jab log` /
# `jab help` resolve the extension via jab's upward be/-scan from the wt cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [bro/$NAME] $*" >&2; exit 1; }

# tty-binding probe (the pager needs tty.size for width); SKIP cleanly if absent.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.size === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo no)
[ "$HAS" = "yes" ] || { echo "bro/help: SKIP — jab has no tty binding" >&2; exit 0; }

# A 1-commit repo is enough for a base view to push help onto.
WT="$WORK/wt"; mkdir -p "$WT/.be"
cd "$WT"
printf 'one\n' > a.txt; "$BE" post 'first commit for the help-screen repro' >/dev/null 2>&1 || _fail "post 1"

# Capture the base view (log:) and the help view (help:) tlv streams.
"$JABC" log:  --tlv >"$WORK/log.tlv"  2>"$WORK/log.err"  || _fail "jab log: --tlv failed ($(cat "$WORK/log.err"))"
"$JABC" help: --tlv >"$WORK/help.tlv" 2>"$WORK/help.err" || _fail "jab help: --tlv failed ($(cat "$WORK/help.err"))"
[ -s "$WORK/log.tlv" ]  || _fail "jab log: --tlv emitted ZERO bytes"
[ -s "$WORK/help.tlv" ] || _fail "jab help: --tlv emitted ZERO bytes"

# Drive the Pager: h pushes help, - backs out, status line reads `h: help`.
"$JABC" "$_CASE/check.js" "$WORK/log.tlv" "$WORK/help.tlv" >"$WORK/check.out" 2>&1 \
    || { cat "$WORK/check.out" >&2; _fail "help-screen assertions failed"; }
grep -q "test/bro/help OK" "$WORK/check.out" || { cat "$WORK/check.out" >&2; _fail "check.js did not report OK"; }

echo "PASS [bro/$NAME]"
