# JAB-003 test/put/putcase.sh — golden-snapshot harness for the hunk-emitting
# `be put` (jab).  Sourced at the top of every test/put/<case>/run.sh.  A case
# BUILDS a baseline once, COPIES it into a single JS tree, mutates it, then
# runs `jab put` and asserts its output against a committed per-case golden
# (jab's own verified-correct snapshot):
#   * stdout (time-normalised) — the `put:` banner + rows + skip lines,
#   * the wtlog `put` rows (verb + URI),
#   * the on-disk file set (renames/claims),
#   * the project-shard `refs` rows (ref-write forms).
# All four are folded into ONE golden stream; the mtime==row-ts restamp
# invariant stays a separate jab-vs-jab behavioral check (no native oracle).
# Native `be put` is retired: native stays columnar while jab emits true hunks,
# so jab-vs-be is phased out (JAB-003).  Golden path: <case_dir>/golden.out.
#
# Self-contained (does NOT source test/lib/case.sh, whose $0-relative paths
# assume a 2-level test/<verb>/<case> layout — this case sits 3 levels deep
# at test/js/put/<case>).  Reuses test/lib/repo-setup.sh for the firewall.
# POSIX sh.  Mirrors test/js/get/../lib/getcase.sh.

set -eu

# --- locate binaries + the put.js extension ---------------------------
_CASE=$(cd "$(dirname "$0")" && pwd)             # test/js/put/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)           # repo root
# TEST-003: jab-only — native `be` is RETIRED (it now LAGS jab), so the whole
# harness runs on jab: locate jab, and alias BE=$JABC so any legacy `"$BE"` seed
# call in a case seeds with jab too.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "putcase: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
# JAB-001: scripts live in the sibling `be/` submodule ($_ROOT/../be).
# GUARD: skip (exit 0) if that cross-submodule path is absent.
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "putcase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }
export BE JABC PUTJS
case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
. "$_ROOT/lib/golden.sh"                          # JAB-003: golden_assert
GOLDEN=${GOLDEN:-$_CASE/golden.out}               # JAB-003: committed snapshot
# Hermetic firewall: an empty `.be` FILE just above the scratch base stops
# `be`'s cwd-walk from escaping to a real $HOME/.be (rs firewall, DIS-024).
WORK="$TMP/$$/js-put/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
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

# TEST-003 fork_pair — copy $BASE into the JS side ($JS).  A jab-seeded baseline
# is a self-contained COLOCATED primary (`.be` dir, store==wt), so `cp -a` is
# enough — no reanchor (that was for native's store-redirect row-0, now retired).
fork_pair() {
    JS="$WORK/js"; rm -rf "$JS"
    cp -a "$BASE" "$JS"
}

# JAB-003 put_both ARGS… — run `jab put ARGS` in $JS, capturing stdout/stderr,
# then golden_assert stdout + wtlog rows + refs + file set as one snapshot
# stream.  Name kept for the cases' call site.  Mutate is the caller's job.
put_both() {
    ( cd "$JS"  && "$JABC" put "$@" ) >"$JS.out" 2>"$JS.err" || true
    _assert_equiv
}

# JAB-003 mutate CMD — apply CMD to the (single) JS side, cd'd into the wt.
mutate() { ( cd "$JS" && eval "$1" ); }

_putrows() {  # verb<TAB>uri for every `put` wtlog row
    "$JABC" "$_CASE/../dumprows.js" "$1/.be/wtlog" put
}
_refrows() {  # verb<TAB>uri for the project-shard refs (if present)
    _shard=$(ls -d "$1"/.be/*/ 2>/dev/null | grep -v '\.be/\.' | head -1)
    [ -n "${_shard:-}" ] && [ -f "$_shard/refs" ] && \
        "$JABC" "$_CASE/../dumprows.js" "$_shard/refs" || true
}
_fileset() { ( cd "$1" && find . -type f | grep -vE '/\.be|^\./\.be' | sort ); }

# JAB-003 _assert_equiv — fold the JS side's stdout + wtlog put rows +
# project refs rows + on-disk file set into ONE labelled stream and
# golden_assert it against the committed <case_dir>/golden.out.
_assert_equiv() {
    {
        echo "=== stdout ==="; cat "$JS.out"
        echo "=== wtlog put rows ==="; _putrows "$JS"
        echo "=== refs rows ==="; _refrows "$JS"
        echo "=== file set ==="; _fileset "$JS"
    } | golden_assert "$NAME" "$GOLDEN"
    # JAB-003: mtime==row-ts restamp is jab's own invariant (JS side only, no
    # native oracle) — kept as a separate behavioral check past the snapshot.
    "$JABC" "$_CASE/../mtimeinv.js" "$JS" || _fail "mtime != row ts (restamp)"
}

pass() { echo "PASS [$NAME]"; }
