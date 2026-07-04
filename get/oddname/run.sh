#!/bin/sh
# JS-075 test/get/oddname — a tracked name containing `#` or `?` must round-trip
# through the `be get` fan-out + leaf: correct bytes on disk, NO spurious unlink.
# The bug: the fan-out row `rel + "?" + newSha + "#" + oldSha` is raw-concat and
# the leaf re-parses it with `new URI` — a `#` in the name empties newSha (the
# leaf then DELETES join(wt,"a")); a `?` truncates rel.  RED-first; SUT=get; JS.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/get/oddname
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "oddname: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-${JAB:-$_BIN/jab}}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "oddname: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "oddname: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/js-get/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# 1. Build a source store whose TREE carries `a#b`, `c?d`, `plain.txt` (the CLI
#    put/post layer cannot stage those names, so build the pack directly).
SRC="$WORK/src"
BECODE="$BEDIR" ODDSTORE="$SRC" "$JABC" "$_CASE/mkstore.js" >/dev/null 2>&1 \
    || _fail "mkstore failed (could not build a#b/c?d source tree)"

# 2. Clone it with the JS `be get` — the fan-out + leaf under test.
CL="$WORK/clone"; mkdir -p "$CL"
( cd "$CL" && "$JABC" get "file://$SRC/.be?/src" ) >"$WORK/get.out" 2>"$WORK/get.err" \
    || _fail "jab get errored: $(tail -1 "$WORK/get.err")"

# 3. Assert: odd-named files materialised with the CORRECT bytes.
[ -f "$CL/a#b" ] || _fail "a#b was NOT checked out (fan-out mis-framed the #)"
[ -f "$CL/c?d" ] || _fail "c?d was NOT checked out (fan-out mis-framed the ?)"
[ "$(cat "$CL/a#b")" = "HASHNAME" ] || _fail "a#b bytes wrong: [$(cat "$CL/a#b")]"
[ "$(cat "$CL/c?d")" = "QUESNAME" ] || _fail "c?d bytes wrong: [$(cat "$CL/c?d")]"
[ "$(cat "$CL/plain.txt")" = "PLAIN" ] || _fail "plain.txt bytes wrong"

# 4. Assert: NO spurious wrong-path file from the truncated rel (`a` / `c`).
[ ! -e "$CL/a" ] || _fail "spurious /a created (# truncation)"
[ ! -e "$CL/c" ] || _fail "spurious /c created (? truncation)"

echo "PASS [$NAME]"
