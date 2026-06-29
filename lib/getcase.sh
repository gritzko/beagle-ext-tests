# test/js/lib/getcase.sh — differential parity harness for `bin/get.js`
# (the pure-JS `be get`, JS-038..041).  Sourced at the top of every
# test/js/get/<case>/run.sh.  Clones the SAME remote with native `be get`
# AND `jabc bin/get.js`, then asserts the two are equivalent: stdout
# (time-normalised), the worktree tree (excl `.be`/`.git`), and `be status`.
#
# Self-contained (does NOT source test/lib/case.sh, whose $0-relative paths
# assume a 2-level test/<verb>/<case> layout — this case sits 3 levels deep
# at test/js/get/<case>).  Reuses test/lib/repo-setup.sh for the hermetic
# `.be` firewall.  POSIX sh.

set -eu

# --- locate binaries + the get.js extension ---------------------------
_CASE=$(cd "$(dirname "$0")" && pwd)            # test/js/get/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)          # repo root
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "getcase: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
# JAB-001: scripts live in the sibling `be/` submodule ($_ROOT/../be), not in
# beagle/bin/.  GUARD: skip (exit 0) if that cross-submodule path is absent.
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "getcase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }
[ -x "$JABC" ] || { echo "getcase: no jab at $JABC" >&2; exit 2; }

# wire transport env (be:/ssh: spawn `ssh <host> keeper upload-pack`; local
# uses $KEEPER_BIN) — point both at the bin dir holding `be`/`keeper`.
: "${KEEPER_BIN:=$_BIN/keeper}"
: "${DOG_REMOTE_PATH:=$_BIN}"
export BE JABC GETJS KEEPER_BIN DOG_REMOTE_PATH
case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
# JSC singleton leaks are suppressed in the unit harness; the extension run
# is a separate process, so silence LSan here too (parity is the assertion).
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
RS_ROOT="$TMP/$$"
# Hermetic base: an empty `.be` FILE just above the scratch stops `be`'s
# cwd-walk from escaping to a real $HOME/.be (rs firewall, DIS-024).
WORK="$TMP/$$/js-get/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
export WORK

# --- assert helpers ---------------------------------------------------
_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# strip the leading 7-col date so two runs at different wall-clocks compare.
_norm() { sed -E 's/^ *[0-9]{1,2}:[0-9]{2} */T /'; }

# tree_eq DIR_A DIR_B — same CONTENT file set + same contents.  Excludes the
# `.be` store/worktree-log (a dir for a primary clone, a FILE for a file://
# secondary wt) and its `..be.idx` sidecar — store metadata, not content
# (native writes the sidecar, the JS clone doesn't; `be status` reads either).
tree_eq() {
    _flt='^\./(\.be(/|$)|\.\.be\.idx$|\.git/)'
    _a=$(cd "$1" && find . -type f | grep -vE "$_flt" | sort)
    _b=$(cd "$2" && find . -type f | grep -vE "$_flt" | sort)
    [ "$_a" = "$_b" ] || { echo "--- A ---"; echo "$_a"; echo "--- B ---"; echo "$_b"; _fail "file set differs"; }
    for _f in $_a; do
        cmp -s "$1/$_f" "$2/$_f" || _fail "content differs: $_f"
    done
}

# get_both REMOTE NDIR JDIR — run native + JS get into the two (existing)
# dirs and assert stdout + tree equivalence.  Leaves the outputs in
# $NDIR.out / $JDIR.out for the caller.
get_both() {
    _remote=$1; _nd=$2; _jd=$3
    ( cd "$_nd" && "$BE" get "$_remote" ) >"$_nd.out" 2>/dev/null
    ( cd "$_jd" && "$JABC" get "$_remote" ) >"$_jd.out" 2>"$_jd.err"
    _norm <"$_nd.out" >"$_nd.norm"
    _norm <"$_jd.out" >"$_jd.norm"
    if ! cmp -s "$_nd.norm" "$_jd.norm"; then
        echo "--- native ---"; cat "$_nd.out"; echo "--- js ---"; cat "$_jd.out"
        _fail "stdout differs"
    fi
    tree_eq "$_nd" "$_jd"
}

# status_eq DIR — `be status` summary line; echoes it (caller compares).
status_line() { ( cd "$1" && "$BE" status 2>/dev/null | tail -1 ); }

# status_both NDIR JDIR — assert `be status` summaries match.
status_both() {
    _ns=$(status_line "$1"); _js=$(status_line "$2")
    [ "$_ns" = "$_js" ] || _fail "be status differs: native[$_ns] js[$_js]"
}

# pass — final marker.
pass() { echo "PASS [$NAME]"; }
