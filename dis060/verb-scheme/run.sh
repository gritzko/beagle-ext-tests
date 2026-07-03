#!/bin/sh
# DIS-060 test/dis060/verb-scheme — a mutation verb must NOT mint a phantom
# `<verb>:` URI scheme in its hunk/banner.  A VERB is not a URI SCHEME (see
# [Nav]/[URI]): the six mutation verbs (get/head/post/put/delete/patch) have no
# read-projection, so `post:`/`put:`/… are category errors.  The columnar
# renderer draws the banner URI next to the 3-char verb column, so a `post:`
# banner prints DOUBLED (`post post:`) on a tty.  This RED-first repro runs
# `jab post` and `jab put` in a scratch wt and asserts NEITHER banner carries a
# `<verb>:` scheme.  SUT=loop; JS-ONLY.  Self-contained (post/colon-msg shape).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/dis060/verb-scheme
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "verb-scheme: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-${JAB:-$_BIN/jab}}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "verb-scheme: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "verb-scheme: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/dis060/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
export BE JABC BEDIR

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# Assert a captured banner stream carries NO phantom `<verb>:` scheme.  The
# banner URI is the hunk header (its first non-blank col); a `<verb>:` there is
# what the renderer doubles into `<verb> <verb>:`.  We scan every line for the
# scheme token both at line start (`put:`) and after the verb column
# (`post post:` / a `post:...` URI anywhere on the banner line).
_assert_no_scheme() {   # _assert_no_scheme VERB FILE
    _v=$1; _f=$2
    if grep -qE "(^|[[:space:]])$_v:" "$_f"; then
        _fail "[$_v] banner mints a phantom '$_v:' scheme (verb == URI scheme):
$(cat "$_f")"
    fi
}

# fresh wt, baseline commit (native be so jab's own banner is not under test in
# the seed), stage a change, then run the JS verb and capture its banner.
_wt="$WORK/wt"; mkdir -p "$_wt/.be"
( cd "$_wt"
  printf 'A\n' > a.txt
  "$BE" post 'base' >/dev/null 2>&1 ) || _fail "baseline seed failed"

# --- put: stage a change with `jab put`, assert no `put:` banner scheme ---
( cd "$_wt"
  sleep 0.02
  printf 'A2\n' > a.txt
  "$JABC" put a.txt ) >"$WORK/put.out" 2>"$WORK/put.err" \
    || _fail "jab put FAILED (non-zero): $(cat "$WORK/put.err")"
grep -qE '^ *put a\.txt' "$WORK/put.out" \
    || _fail "jab put produced no staging row: $(cat "$WORK/put.out")"
_assert_no_scheme put "$WORK/put.out"
echo "ok: jab put banner carries no 'put:' scheme"

# --- post: commit the staged change with `jab post`, assert no `post:` ----
( cd "$_wt" && "$JABC" post 'change' ) >"$WORK/post.out" 2>"$WORK/post.err" \
    || _fail "jab post FAILED (non-zero): $(cat "$WORK/post.err")"
grep -qE '^ *mod a\.txt' "$WORK/post.out" \
    || _fail "jab post produced no commit row: $(cat "$WORK/post.out")"
_assert_no_scheme post "$WORK/post.out"
echo "ok: jab post banner carries no 'post:' scheme"

echo "PASS [$NAME]"
