# JAB-003 test/lib/getcase.sh — golden-snapshot harness for the hunk-emitting
# `be get` (jab, JS-038..041).  Sourced at the top of every
# test/get/<case>/run.sh.  A case clones a remote with `jab get` and asserts
# its output against a committed per-case golden (jab's own verified-correct
# snapshot): stdout (date-normalised), the checked-out worktree (excl
# `.be`/`.git`), and `jab status`.  No native `be get` oracle: native `be`
# stays columnar while jab emits true hunks, so jab-vs-be is retired (JAB-003).
# Golden path: <case_dir>/golden.out (see lib/golden.sh).
#
# Self-contained (does NOT source test/lib/case.sh, whose $0-relative paths
# assume a 2-level test/<verb>/<case> layout — this case sits 3 levels deep
# at test/js/get/<case>).  Reuses test/lib/repo-setup.sh for the hermetic
# `.be` firewall.  POSIX sh.

set -eu

# --- locate binaries + the get.js extension ---------------------------
_CASE=$(cd "$(dirname "$0")" && pwd)            # test/js/get/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)          # repo root
# TEST-003: jab-only — native `be` is RETIRED (it now LAGS jab), so drop the
# `[ -x "$BE" ]` gate: locate jab, then alias BE=$JABC so any legacy `"$BE"`
# seed/put/post/delete in a case seeds with jab too.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "getcase: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
# JAB-001: scripts live in the sibling `be/` submodule ($_ROOT/../be), not in
# beagle/bin/.  GUARD: skip (exit 0) if that cross-submodule path is absent.
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "getcase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

# wire transport env (be:/ssh: spawn `ssh <host> keeper upload-pack`; local
# uses $KEEPER_BIN) — point both at the bin dir holding `be`/`keeper`.
: "${KEEPER_BIN:=$_BIN/keeper}"
: "${DOG_REMOTE_PATH:=$_BIN}"
export BE JABC GETJS KEEPER_BIN DOG_REMOTE_PATH
case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
# JSC singleton leaks are suppressed in the unit harness; the extension run
# is a separate process, so silence LSan here too.
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
. "$_ROOT/lib/golden.sh"                          # JAB-003: golden_assert
GOLDEN=${GOLDEN:-$_CASE/golden.out}               # JAB-003: committed snapshot
RS_ROOT="$TMP/$$"
# Hermetic base: an empty `.be` FILE just above the scratch stops `be`'s
# cwd-walk from escaping to a real $HOME/.be (rs firewall, DIS-024).
WORK="$TMP/$$/js-get/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export WORK

# --- assert helpers ---------------------------------------------------
_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# JAB-003: accumulate labelled probe blocks; pass() golden_asserts the whole
# stream (a case may clone/status several times → one golden per case).
_GSTREAM="$WORK/golden.stream"; : > "$_GSTREAM"

# JAB-003 tree_dump DIR — emit the CONTENT file set + each file's bytes.
# Excludes the `.be` store/worktree-log + its `..be.idx` sidecar + `.git`
# (store metadata, not content).
tree_dump() {
    _flt='^\./(\.be(/|$)|\.\.be\.idx$|\.git/)'
    _fs=$(cd "$1" && find . -type f | grep -vE "$_flt" | sort)
    echo "$_fs"
    for _f in $_fs; do echo "--- $_f ---"; cat "$1/$_f"; done
}

# JAB-003 _gnorm — fold the volatile per-run commit hash (7-40 hex after `#`
# or bare `?`) to `H`; the stable ref sigil (`?master`) + message stay.
_gnorm() { sed -E 's/([#?])[0-9a-f]{7,40}/\1H/g'; }

# JAB-003 get_both REMOTE _ JDIR — run `jab get` into the (existing) JS dir,
# capturing stdout, then append hash-folded stdout + worktree dump to the
# golden stream (the volatile scratch-path REMOTE is kept OUT of the golden).
# 3-arg signature kept for the cases' call site; the native dir arg is ignored.
get_both() {
    _remote=$1; _jd=$3
    ( cd "$_jd" && "$JABC" get "$_remote" ) >"$_jd.out" 2>"$_jd.err"
    {
        echo "=== get stdout ==="; _gnorm <"$_jd.out"
        echo "=== worktree ==="; tree_dump "$_jd"
    } >>"$_GSTREAM"
}

# JAB-003 status_line DIR — `jab status` output; echoes it (caller compares).
status_line() { ( cd "$1" && "$JABC" status 2>/dev/null ); }

# JAB-003 status_both _ JDIR — append the JS side's `jab status` to the stream.
# 2-arg signature kept; the native dir arg is ignored.
status_both() {
    { echo "=== status ==="; status_line "$2"; } >>"$_GSTREAM"
}

# JAB-003 pass — golden_assert the accumulated stream, then print the marker.
# Cases with no probe (self-checking E2E) leave the stream empty → no assert.
pass() {
    [ -s "$_GSTREAM" ] && golden_assert "$NAME" "$GOLDEN" <"$_GSTREAM"
    echo "PASS [$NAME]"
}
