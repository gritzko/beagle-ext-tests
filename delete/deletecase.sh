# JAB-003 test/delete/deletecase.sh — golden-snapshot harness for the
# hunk-emitting `be delete` (jab).  Sourced at the top of every
# test/delete/<case>/run.sh.  A case BUILDS a baseline once, COPIES it into a
# single JS tree, mutates it, then runs `jab delete` and asserts its output
# against a committed per-case golden (jab's own verified-correct snapshot):
#   * stdout (date-normalised) — the `delete:` hunk banner + rows + summary,
#   * the wtlog `delete` rows (verb + URI),
#   * the on-disk file set (which files got unlinked),
#   * the project-shard `refs` rows (branch tombstones).
# All four are folded into ONE golden stream.  No native `be delete` oracle:
# native `be` stays columnar while jab emits true hunks, so jab-vs-be is
# retired (JAB-003).  Golden path: <case_dir>/golden.out (see lib/golden.sh).
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
. "$_ROOT/lib/golden.sh"                          # JAB-003: golden_assert
GOLDEN=${GOLDEN:-$_CASE/golden.out}               # JAB-003: committed snapshot
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

# --- baseline + per-side copies ---------------------------------------
# seed_baseline CMD — run CMD (file-seed shell) inside a fresh wt, commit a
# baseline, and stash it at $WORK/base.  Sets $BASE.
seed_baseline() {
    BASE="$WORK/base"; rm -rf "$BASE"; mkdir -p "$BASE"
    ( cd "$BASE" && mkdir .be && eval "$1" && "$BE" post 'base' >/dev/null 2>&1 )
}

# JAB-003 fork_pair — copy $BASE into the JS side ($JS) and re-anchor its
# row-0 at its OWN `.be` (cp -a leaves the anchor pinned at $BASE; reanchor.js
# repoints it).  Single side now — the native oracle is retired.
fork_pair() {
    JS="$WORK/js"; rm -rf "$JS"
    cp -a "$BASE" "$JS"
    "$JABC" "$_CASE/../../lib/reanchor.js" "$JS"
}

# JAB-003 delete_both ARGS… — run `jab delete ARGS` in $JS, capturing
# stdout/stderr, then golden_assert stdout + wtlog rows + refs + file set as
# one snapshot stream.  Name kept for the cases' call site.  Mutate is theirs.
delete_both() {
    ( cd "$JS"  && "$JABC" delete "$@" ) >"$JS.out" 2>"$JS.err" || true
    _assert_equiv
}

# JAB-003 mutate CMD — apply CMD to the (single) JS side, cd'd into the wt.
mutate() { ( cd "$JS" && eval "$1" ); }

_delrows() {  # verb<TAB>uri for every `delete` wtlog row
    "$JABC" "$_CASE/../../put/dumprows.js" "$1/.be/wtlog" delete
}
_refrows() {  # verb<TAB>uri for the project-shard refs (if present)
    _shard=$(ls -d "$1"/.be/*/ 2>/dev/null | grep -v '\.be/\.' | head -1)
    [ -n "${_shard:-}" ] && [ -f "$_shard/refs" ] && \
        "$JABC" "$_CASE/../../put/dumprows.js" "$_shard/refs" || true
}
_fileset() { ( cd "$1" && find . -type f | grep -vE '/\.be|^\./\.be' | sort ); }

# JAB-003 _assert_equiv — fold the JS side's stdout + wtlog delete rows +
# project refs rows + on-disk file set into ONE labelled stream and
# golden_assert it against the committed <case_dir>/golden.out.
_assert_equiv() {
    {
        echo "=== stdout ==="; cat "$JS.out"
        echo "=== wtlog delete rows ==="; _delrows "$JS"
        echo "=== refs rows ==="; _refrows "$JS"
        echo "=== file set ==="; _fileset "$JS"
    } | golden_assert "$NAME" "$GOLDEN"
}

pass() { echo "PASS [$NAME]"; }
