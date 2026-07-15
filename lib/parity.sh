# test/js/lib/parity.sh — TEST-003 jab-only harness (was JSQUE-007 native-vs-jab
# parity).  Native `be` is RETIRED: it LAGS jab, so the OLD native side (run_native,
# the $NAT fork, and the native-vs-jab cmp asserts) is GONE.  What remains is the
# jab RUN scaffolding — locate jab, seed a baseline WITH jab, fork ONE JS copy, and
# run the JS path — so cases assert jab INTRINSICALLY (self-contained golden /
# structure), mirroring test/commit/*.  POSIX sh.  Models test/js/lib/{get,put}case.sh.
#
# SUT SELECTOR — $SUT picks the JS path a case runs:
#   SUT=oneshot            → `jab  be/<verb>.js  ARGS`   (the landed per-verb script)
#   SUT=loop  (default)    → `jab  <verb>  ARGS`         (the JSQUE-002 resident loop)
# A case never spells the JS command; it calls run_js and the selector resolves it.
# ($SUT_JS overrides the script path outright for ad-hoc runs.)
#
# Self-contained (does NOT source test/lib/case.sh — these cases sit 3 levels
# deep at test/<topic>/<case>).  Reuses test/lib/repo-setup.sh for the hermetic
# `.be` firewall.

set -eu

# --- locate jab + the be/ extension dir -------------------------------
_CASE=$(cd "$(dirname "$0")" && pwd)             # test/<topic>/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)           # repo root (beagle/)
# TEST-003: jab-only — native `be` is RETIRED (it LAGS jab); locate jab and
# alias BE=$JABC so legacy `"$BE" post` seeds run jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-${JAB:-$(command -v jab || true)}}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "parity: cannot locate jab (set BIN= or JABC=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
# JAB-001: scripts live in the sibling `be/` submodule ($_ROOT/../be), not in
# beagle/bin/.  GUARD: skip (exit 0) if that cross-submodule path is absent.
# JSQUE-008: a $BEDIR override lets an isolated worktree gate its OWN be/ shard.
BEDIR="${BEDIR:-$_ROOT/..}"
[ -d "$BEDIR" ] || { echo "parity: SKIP — no be/ submodule at $BEDIR" >&2; exit 0; }

# wire transport env (file:/be: local keeper) — point at the bin dir.
: "${KEEPER_BIN:=$_BIN/keeper}"
: "${DOG_REMOTE_PATH:=$_BIN}"
: "${SUT:=loop}"                                  # loop | oneshot
# Loop-mode pre-flight (hoisted ABOVE any subshell): if the case targets the
# resident loop but be/main.js has not landed yet, SKIP the whole case cleanly.
if [ "$SUT" = loop ] && [ -z "${SUT_JS:-}" ] && [ ! -f "$BEDIR/main.js" ]; then
    echo "parity: SKIP — SUT=loop but no $BEDIR/main.js yet" >&2; exit 0
fi
export BE JABC BEDIR KEEPER_BIN DOG_REMOTE_PATH SUT
case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
# Hermetic firewall: an empty `.be` FILE just above the scratch base stops
# `be`'s cwd-walk from escaping to a real $HOME/.be (rs firewall, DIS-024).
WORK="$TMP/$$/js-parity/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export WORK

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
pass()  { echo "PASS [$NAME]"; }

# --- normalisation: date column + hunk framing ------------------------
# 1. collapse the leading wall-clock date column to a constant `T `.
# 2. jab verbs emit TRUE HUNKS — drop the bare `<scheme>:` banner line and the
#    trailing blank so the columnar BODY compares stably run-to-run.
_norm() {
    sed -E 's/^ *[0-9]{1,2}:[0-9]{2} +/T /' \
  | sed -E '/^[a-z][a-z0-9]*:/d' \
  | awk 'NF{last=NR} {ln[NR]=$0} END{for(i=1;i<=last;i++)print ln[i]}'
}

# --- the SUT selector: the JS path ------------------------------------
# run_js VERB ARGS…  — run the JS path for VERB in $PWD, per $SUT:
#   oneshot → jab be/<verb>.js ARGS         (the landed per-verb script)
#   loop    → jab <verb> ARGS               (the JSQUE-002 resident loop)
# $SUT_JS, if set, overrides the resolved script path verbatim.
run_js() {
    _v=$1; shift
    if [ -n "${SUT_JS:-}" ]; then
        "$JABC" "$SUT_JS" "$@"; return $?
    fi
    case "$SUT" in
        loop)
            _js="$BEDIR/main.js"
            [ -f "$_js" ] || { echo "parity: SKIP — SUT=loop but no $_js yet" >&2; exit 0; }
            "$JABC" "$_v" "$@" ;;
        oneshot|*)
            _js="$BEDIR/$_v.js"
            [ -f "$_js" ] || { echo "parity: SKIP — no $_js for verb $_v" >&2; exit 0; }
            "$JABC" "$_js" "$@" ;;
    esac
}

# --- row probes (dump wtlog/refs rows for intrinsic structure asserts) -
# _rows ULOG-PATH [VERB] — dump `<verb>\t<uri>` rows (optionally filtered).
# dumprows.js writes via io.log → fd 2, so fold stderr→stdout to capture rows.
_rows() { "$JABC" "$_CASE/../dumprows.js" "$1" "${2:-}" 2>&1; }
_wtlog_rows() { _rows "$1/.be/wtlog" "${2:-}"; }
_refs_rows() {
    _shard=$(ls -d "$1"/.be/*/ 2>/dev/null | grep -v '/\.be/\.' | head -1)
    [ -n "${_shard:-}" ] && [ -f "$_shard/refs" ] && _rows "$_shard/refs" || true
}

# --- baseline + JS fork (mirrors putcase.sh) --------------------------
# seed_baseline CMD — build a committed baseline in $WORK/base via jab; $BASE set.
seed_baseline() {
    BASE="$WORK/base"; rm -rf "$BASE"; mkdir -p "$BASE"
    ( cd "$BASE" && mkdir .be && eval "$1" && "$BE" post 'base' >/dev/null 2>&1 )
}

# TEST-003 fork_pair — copy $BASE into the JS side ($JS) ONLY.  A jab-seeded
# baseline is a self-contained COLOCATED primary (store==wt), so `cp -a` is
# enough — no reanchor (that was native's store-redirect row-0, now retired).
# Name kept (cases call fork_pair); the native $NAT fork is GONE.
fork_pair() {
    JS="$WORK/js"; rm -rf "$JS"
    cp -a "$BASE" "$JS"
}

# mutate CMD — apply CMD to the (single) JS side, cd'd into the wt.
mutate() { ( cd "$JS" && eval "$1" ); }

# --- one-call verb run over the JS fork -------------------------------
# verb_run VERB ARGS… — run the JS path for VERB in $JS, capturing stdout/stderr
# at $JS.out / $JS.err.  Intrinsic assertion is the caller's job.  (Was
# verb_parity — the native run + native-vs-jab cmp is RETIRED.)
verb_run() {
    _vp_verb=$1; shift
    ( cd "$JS" && run_js "$_vp_verb" "$@" ) >"$JS.out" 2>"$JS.err" || true
}

# --- content-tree equality (for get/clone-model cases) ----------------
# tree_eq A B — same CONTENT file set + same contents (excl `.be`/`.git`).
tree_eq() {
    _flt='^\./(\.be(/|$)|\.\.be\.idx$|\.git/)'
    _a=$(cd "$1" && find . -type f | grep -vE "$_flt" | sort)
    _b=$(cd "$2" && find . -type f | grep -vE "$_flt" | sort)
    [ "$_a" = "$_b" ] || { echo "--- A ---"; echo "$_a"; echo "--- B ---"; echo "$_b"; _fail "file set differs"; }
    for _f in $_a; do
        cmp -s "$1/$_f" "$2/$_f" || _fail "content differs: $_f"
    done
}
