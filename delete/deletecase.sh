# test/js/delete/deletecase.sh — differential parity harness for
# `bin/delete.js` (the pure-JS `be delete`, JS-050).  Sourced at the top of
# every test/js/delete/<case>/run.sh.  A case BUILDS a baseline once, COPIES
# it into a native tree and a JS tree, mutates BOTH identically, then runs
# native `be delete` vs `jabc bin/delete.js` and asserts they are equivalent:
#   * stdout (time-normalised) — the `delete:` banner + rows + summary lines,
#   * the wtlog `delete` rows (verb + URI),
#   * the on-disk file set (which files got unlinked),
#   * the project-shard `refs` rows (branch tombstones).
# DELETE does NOT restamp (the file is gone), so there is no mtime invariant.
#
# Self-contained (does NOT source test/lib/case.sh, whose $0-relative paths
# assume a 2-level layout — this case sits 3 levels deep at
# test/js/delete/<case>).  Reuses test/lib/repo-setup.sh for the firewall.
# POSIX sh.  Mirrors test/js/put/putcase.sh.

set -eu

# --- locate binaries + the delete.js extension ------------------------
_CASE=$(cd "$(dirname "$0")" && pwd)             # test/js/delete/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)           # repo root
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "deletecase: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
# JAB-001: scripts live in the sibling `be/` submodule ($_ROOT/../be).
# GUARD: skip (exit 0) if that cross-submodule path is absent.
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "deletecase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }
[ -x "$JABC" ] || { echo "deletecase: no jab at $JABC" >&2; exit 2; }
export BE JABC DELJS
case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
# Hermetic firewall: an empty `.be` FILE just above the scratch base stops
# `be`'s cwd-walk from escaping to a real $HOME/.be (rs firewall, DIS-024).
WORK="$TMP/$$/js-delete/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
export WORK

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# strip the leading 7-col date so two runs at different wall-clocks compare.
_norm() { sed -E 's/^ *[0-9]{1,2}:[0-9]{2} +/T /'; }

# --- baseline + per-side copies ---------------------------------------
# seed_baseline CMD — run CMD (file-seed shell) inside a fresh wt, commit a
# baseline, and stash it at $WORK/base.  Sets $BASE.
seed_baseline() {
    BASE="$WORK/base"; rm -rf "$BASE"; mkdir -p "$BASE"
    ( cd "$BASE" && mkdir .be && eval "$1" && "$BE" post 'base' >/dev/null 2>&1 )
}

# fork_pair — copy $BASE into a native side ($NAT) and a JS side ($JS), then
# re-anchor each fork's row-0 at its OWN `.be` so the two stores are isolated
# (cp -a leaves the anchor pinned at $BASE, colliding ref writes; reanchor.js
# repoints it — the cp -a already duplicated the project shard).
fork_pair() {
    NAT="$WORK/nat"; JS="$WORK/js"; rm -rf "$NAT" "$JS"
    cp -a "$BASE" "$NAT"; cp -a "$BASE" "$JS"
    "$JABC" "$_CASE/../../lib/reanchor.js" "$NAT"
    "$JABC" "$_CASE/../../lib/reanchor.js" "$JS"
}

# delete_both ARGS… — run native `be delete ARGS` in $NAT and
# `jabc delete.js ARGS` in $JS, capturing stdout/stderr, then assert
# stdout + wtlog rows + file set + refs.  Mutate is the caller's job.
delete_both() {
    ( cd "$NAT" && "$BE" delete "$@" ) >"$NAT.out" 2>"$NAT.err" || true
    ( cd "$JS"  && "$JABC" delete "$@" ) >"$JS.out" 2>"$JS.err" || true
    _assert_equiv
}

# mutate BOTH sides identically by running CMD in each (cd'd into the wt).
mutate() {
    ( cd "$NAT" && eval "$1" )
    ( cd "$JS"  && eval "$1" )
}

_delrows() {  # verb<TAB>uri for every `delete` wtlog row
    "$JABC" "$_CASE/../../put/dumprows.js" "$1/.be/wtlog" delete
}
_refrows() {  # verb<TAB>uri for the project-shard refs (if present)
    _shard=$(ls -d "$1"/.be/*/ 2>/dev/null | grep -v '\.be/\.' | head -1)
    [ -n "${_shard:-}" ] && [ -f "$_shard/refs" ] && \
        "$JABC" "$_CASE/../../put/dumprows.js" "$_shard/refs" || true
}
_fileset() { ( cd "$1" && find . -type f | grep -vE '/\.be|^\./\.be' | sort ); }

_assert_equiv() {
    _norm <"$NAT.out" >"$NAT.norm"; _norm <"$JS.out" >"$JS.norm"
    cmp -s "$NAT.norm" "$JS.norm" || {
        echo "--- native ---"; cat "$NAT.out"; echo "--- js ---"; cat "$JS.out"
        _fail "stdout differs"; }
    _delrows "$NAT" >"$NAT.rows"; _delrows "$JS" >"$JS.rows"
    cmp -s "$NAT.rows" "$JS.rows" || {
        echo "--- native rows ---"; cat "$NAT.rows"; echo "--- js rows ---"; cat "$JS.rows"
        _fail "wtlog delete rows differ"; }
    _refrows "$NAT" >"$NAT.refs"; _refrows "$JS" >"$JS.refs"
    cmp -s "$NAT.refs" "$JS.refs" || {
        echo "--- native refs ---"; cat "$NAT.refs"; echo "--- js refs ---"; cat "$JS.refs"
        _fail "refs rows differ"; }
    _fileset "$NAT" >"$NAT.files"; _fileset "$JS" >"$JS.files"
    cmp -s "$NAT.files" "$JS.files" || {
        echo "--- native files ---"; cat "$NAT.files"; echo "--- js files ---"; cat "$JS.files"
        _fail "on-disk file set differs"; }
}

pass() { echo "PASS [$NAME]"; }
