# test/lib/getrepro.sh — JS-self repro harness for `be get` GET.mkd cases
# (DIS-055).  Unlike getcase.sh (differential JS-vs-native), these assert the
# JS `be get` behaviour DIRECTLY against the spec — several cases (detach on
# `?<sha>`, dirty re-apply) follow GET.mkd, which is NEWER than the C impl, so a
# native diff is not the oracle here.  POSIX sh.
#
# Exposes: $BE (native, for the source-repo setup only), $JAB (the loop the
# tests exercise), $WORK (scratch), and helpers gr_src / gr_jclone / asserts.

set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)            # test/get/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)               # repo root
# TEST-003: jab-only — native `be` RETIRED (LAGS jab); drop the `[ -x "$BE" ]`
# gate, locate jab, and alias BE=$JABC so the source-repo setup seeds with jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "getrepro: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "getrepro: SKIP — no $BEDIR/main.js" >&2; exit 0; }

: "${KEEPER_BIN:=$_BIN/keeper}"
: "${DOG_REMOTE_PATH:=$_BIN}"
export BE JABC KEEPER_BIN DOG_REMOTE_PATH
case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/js-getr/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export WORK

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [$NAME]"; }

# gr_src NAME — create a source repo under $WORK/NAME with an initial commit
# (a.txt=A, b.txt=B, m.txt=M, d/c.txt=C), echo its path.  cd's into it.
gr_src() {
    _s="$WORK/$1"; mkdir -p "$_s"; cd "$_s"; mkdir .be
    printf 'A\n' > a.txt; printf 'B\n' > b.txt; printf 'M\n' > m.txt
    mkdir d; printf 'C\n' > d/c.txt
    "$BE" post 'c1' >/dev/null 2>&1
    printf '%s\n' "$_s"
}

# gr_jclone SRC DST — JS-clone SRC into the (made) DST dir.  TEST-003: a
# jab-seeded source is a single-shard UNNAMED-project colocated primary, so the
# clone URI carries NO `?/name` (a named-project `?/x` misses jab's `?`-trunk).
gr_jclone() {
    mkdir -p "$2"
    ( cd "$2" && "$JABC" get "file://$1/.be" ) >/dev/null 2>&1
}

# gr_jget DIR ARG... — run the JS `be get` in DIR; stdout->$WORK/last.out,
# stderr->$WORK/last.err; echoes the exit code (never aborts under set -e).
gr_jget() {
    _d=$1; shift
    _rc=0
    ( cd "$_d" && "$JABC" get "$@" ) >"$WORK/last.out" 2>"$WORK/last.err" || _rc=$?
    printf '%s\n' "$_rc"
}

# gr_file_is PATH EXPECTED — assert PATH's content equals EXPECTED (a string).
gr_file_is() {
    [ -f "$1" ] || _fail "missing file: $1"
    _got=$(cat "$1")
    [ "$_got" = "$2" ] || _fail "content of $1: got [$_got] want [$2]"
}

# gr_tip_sha SRC — echo the full 40-hex CURRENT trunk tip sha of source SRC
# (the LAST refs row — the newest post).  TEST-003: a jab-seeded source is
# single-shard/unnamed, so refs sits at `.be/refs`, not `.be/<name>/refs`.
gr_tip_sha() {
    od -An -c "$1/.be/refs" 2>/dev/null \
        | tr -d ' \n' | grep -oE '#[0-9a-f]{40}' | tail -1 | tr -d '#'
}

# gr_wtraw DIR — echo the JS clone's wtlog (DIR/.be) as a flat printable string
# (od -c, drop spaces/newlines AND the literal `\t`/`\n` od escapes).
gr_wtraw() {
    od -An -c "$1/.be" 2>/dev/null | tr -d ' \n' | sed 's/\\t//g; s/\\n//g'
}

# gr_wtlog_has DIR PATTERN — assert the wtlog carries a row matching PATTERN.
gr_wtlog_has() {
    gr_wtraw "$1" | grep -qE "$2" \
        || { echo "--- wtlog dump ---"; gr_wtraw "$1"; echo; \
             _fail "wtlog lacks pattern: $2"; }
}
