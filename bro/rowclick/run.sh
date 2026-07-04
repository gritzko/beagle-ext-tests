#!/bin/sh
# test/bro/rowclick — BRO-005 follow-up: EVERY row of a `jab log:` listing is
# clickable across its WHOLE span (sha8 + date + summary + author + soft-wrap
# tail), not just the 8-char sha.  Repro for the live bug: row 1 navigated on a
# left-click but later rows' non-sha columns did not — `_uriAt` only lit the one
# token before the `U`, so the bulk of each commit row read as a dead link.
# Builds a 3-commit chain, captures `jab log: --tlv`, then drives the Pager's
# click path (_screenToByte -> _uriAt) on rows 1/2/3 at the sha column AND a
# non-sha column, asserting EACH resolves to that row's commit:?<sha>.  Also
# guards cat-style many-U-per-line word links stay token-precise.  Registered
# by the be/test glob as be-js-bro-rowclick — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/bro/rowclick
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "bro/rowclick: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "bro/rowclick: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/views/bro/pager.js" ] || { echo "bro/rowclick: SKIP — no pager.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "bro/rowclick: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

# SKIP if the jab build lacks the tty binding (the pager is blocked pre-JS-053).
HAS=$("$JABC" -e 'var b=io.buf(4);b.feed(utf8.Encode(typeof tty==="object"&&typeof tty.size==="function"?"yes":"no"));io.writeAll(1,b);' 2>/dev/null || echo no)
# Some jab builds lack `-e`; fall back to a temp probe below if needed.

: "${TMP:=/tmp}"; export TMP
NAME=rowclick
WORK="$TMP/$$/bro/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink so bareword `jab log`
# resolves the extension via jab's upward be/-scan from the worktree cwd.
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
[ "$HAS" = "yes" ] || { echo "bro/rowclick: SKIP — jab has no tty binding" >&2; exit 0; }

# A 3-commit chain.  `post` auto-stages on first commit; later new files need an
# explicit `put` before they can be posted (else POSTNONE).
WT="$WORK/wt"; mkdir -p "$WT/.be"
cd "$WT"
printf 'one\n'   > a.txt;                       "$BE" post 'first commit summary that is long enough to soft-wrap a narrow row' >/dev/null 2>&1 || _fail "post 1"
printf 'two\n'   > b.txt; "$BE" put b.txt >/dev/null 2>&1; "$BE" post 'second commit summary also reasonably long for wrapping' >/dev/null 2>&1 || _fail "post 2"
printf 'three\n' > c.txt; "$BE" put c.txt >/dev/null 2>&1; "$BE" post 'third commit summary likewise long enough to overflow' >/dev/null 2>&1 || _fail "post 3"

# Expected commit:?<full-sha> per row, newest-first (the native oracle order).
"$BE" log: --tlv 2>/dev/null > "$WORK/nat.tlv"
WANT=$(strings "$WORK/nat.tlv" | grep -o 'commit:?[0-9a-f]\{40\}' || true)
[ -n "$WANT" ] || _fail "native be log: --tlv carries no commit:?<sha> targets"

# Capture the JS loop's --tlv stream (the thing under test).
"$JABC" log: --tlv >"$WORK/jab.tlv" 2>"$WORK/jab.err" || _fail "jab log: --tlv failed ($(cat "$WORK/jab.err"))"
[ -s "$WORK/jab.tlv" ] || _fail "jab log: --tlv emitted ZERO bytes"

# Drive the Pager click path: every row, sha AND non-sha column → its commit.
# shellcheck disable=SC2086
"$JABC" "$_CASE/check.js" "$WORK/jab.tlv" $WANT >"$WORK/check.out" 2>&1 \
    || { cat "$WORK/check.out" >&2; _fail "row-click assertions failed"; }
grep -q "test/bro/rowclick OK" "$WORK/check.out" || { cat "$WORK/check.out" >&2; _fail "check.js did not report OK"; }

echo "PASS [bro/$NAME]"
