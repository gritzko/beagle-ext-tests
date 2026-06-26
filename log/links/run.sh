#!/bin/sh
# test/log/links — BRO-006: `jab log:` emits a `U` click-target per commit row
# (the producer half of BRO-005 mouse nav).  Mirrors C graf/LOG.c:260
# (GRAFPackUriCommitSha → GRAF.c:535 tok32Pack('U', …)): every row links to
# `commit:?<full-sha>`.  Builds a 3-commit chain, captures `jab log: --tlv`,
# and asserts each row's sha8 token is followed by a `U` token whose hidden
# bytes ARE that commit's URI (the pager `_uriAt` contract).  LOG-001's plain
# rows must survive (U bytes hidden).  Registered by the be/test glob as
# be-js-log-links — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/log/links
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "log/links: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "log/links: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "log/links: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=links
WORK="$TMP/$$/log/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink so bareword `jab log`
# resolves the extension via jab's upward be/-scan from the worktree cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sf "$BEDIR" "$TMP/$$/be" 2>/dev/null || true

_fail() { echo "FAIL [log/$NAME] $*" >&2; exit 1; }

# A 3-commit chain.  `post` auto-stages on first commit; new files thereafter
# need an explicit `put` before they can be posted (else POSTNONE).
WT="$WORK/wt"; mkdir -p "$WT/.be"
cd "$WT"
printf 'one\n'   > a.txt;                       "$BE" post 'first commit'  >/dev/null 2>&1 || _fail "post 1"
printf 'two\n'   > b.txt; "$BE" put b.txt >/dev/null 2>&1; "$BE" post 'second commit' >/dev/null 2>&1 || _fail "post 2"
printf 'three\n' > c.txt; "$BE" put c.txt >/dev/null 2>&1; "$BE" post 'third commit'  >/dev/null 2>&1 || _fail "post 3"

# Newest-first list of full 40-hex shas (the log walk order).  `be log: --plain`
# prints the sha8 newest-first; resolve each to its full sha for the U URIs.
"$BE" log: --plain 2>/dev/null | awk 'NF && $1 ~ /^[0-9a-f]{8}$/ { print $1 }' > "$WORK/short"
[ -s "$WORK/short" ] || _fail "no commit rows in be log:"

# Expected commit:?<full-sha> per row (resolve short -> full via tipsha-style
# lookup over the keeper).  The trunk tip is row 0; rebuild the chain order by
# walking native `be log: --tlv` strings (the C oracle already carries the URIs).
"$BE" log: --tlv 2>/dev/null > "$WORK/nat.tlv"
# Pull the C-emitted commit:?<sha> targets, newest-first (the oracle order).
WANT=$(strings "$WORK/nat.tlv" | grep -o 'commit:?[0-9a-f]\{40\}' || true)
[ -n "$WANT" ] || _fail "native be log: --tlv carries no commit:?<sha> targets (oracle)"
NWANT=$(printf '%s\n' "$WANT" | wc -l | tr -d ' ')
NROWS=$(wc -l < "$WORK/short" | tr -d ' ')
[ "$NWANT" = "$NROWS" ] || _fail "native U-target count $NWANT != row count $NROWS"

# Capture the JS loop's --tlv stream (the thing under test).
"$JABC" log: --tlv >"$WORK/jab.tlv" 2>"$WORK/jab.err" || _fail "jab log: --tlv failed ($(cat "$WORK/jab.err"))"
[ -s "$WORK/jab.tlv" ] || _fail "jab log: --tlv emitted ZERO bytes"

# Assert: every commit row in the JS output emits a `U` → commit:?<full-sha>,
# matching the native oracle order, and LOG-001's plain rows survive.
# shellcheck disable=SC2086
"$JABC" "$_CASE/check.js" "$WORK/jab.tlv" $WANT >"$WORK/check.out" 2>&1 \
    || { cat "$WORK/check.out" >&2; _fail "U-target assertions failed"; }
grep -q "test/log/links OK" "$WORK/check.out" || { cat "$WORK/check.out" >&2; _fail "check.js did not report OK"; }

echo "PASS [log/$NAME]"
