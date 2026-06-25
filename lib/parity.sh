# test/js/lib/parity.sh — JSQUE-007 golden-diff parity harness.
#
# A FULL-LINE byte-diff oracle that asserts a verb's stdout (and, optionally,
# its wtlog/refs rows) is BYTE-equivalent between native `be <verb> …` and the
# JS path.  Unlike test/js/{ulog,hunk}.js (substring/indexOf checks), this
# compares EVERY line byte-for-byte after one normalisation: the leading
# wall-clock date column is collapsed to a constant token so two runs at
# different seconds still compare (date column, verb pad, row order, and
# trailing newlines are otherwise preserved).  This is the gate that every
# JSQUE per-verb conversion must pass.
#
# SUT SELECTOR (the one knob the migration flips) — $SUT picks the JS path:
#   SUT=oneshot  (default)  → `jab  be/<verb>.js  ARGS`   (today's scripts)
#   SUT=loop                → `jab  be/main.js  <verb> ARGS`  (JSQUE-002 loop)
# A case never spells the JS command itself; it calls run_js / verb_parity and
# the selector resolves it.  So the SAME case file gates BOTH the current
# one-shot script and the future resident loop, with no edit — only `SUT=loop`.
# ($SUT_JS overrides the script path outright for ad-hoc / broken-oracle runs.)
#
# Self-contained (does NOT source test/lib/case.sh — these cases sit 3 levels
# deep at test/js/parity/<case>).  Reuses test/lib/repo-setup.sh for the
# hermetic `.be` firewall.  POSIX sh.  Models test/js/lib/{get,put}case.sh.

set -eu

# --- locate binaries + the be/ extension dir --------------------------
_CASE=$(cd "$(dirname "$0")" && pwd)             # test/js/parity/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)           # repo root (beagle/)
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "parity: cannot locate be (set BE= or BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-${JAB:-$_BIN/jab}}
# JAB-001: scripts live in the sibling `be/` submodule ($_ROOT/../be), not in
# beagle/bin/.  GUARD: skip (exit 0) if that cross-submodule path is absent.
# JSQUE-008: a $BEDIR override lets an isolated worktree gate its OWN be/ shard
# (the agent's CODE lives in ~/todo/<TICKET>, not the landed beagle-ext) — the
# default is unchanged for the in-tree run.
BEDIR="${BEDIR:-$_ROOT/..}"
[ -d "$BEDIR" ] || { echo "parity: SKIP — no be/ submodule at $BEDIR" >&2; exit 0; }
[ -x "$JABC" ] || { echo "parity: no jab at $JABC" >&2; exit 2; }

# wire transport env (file:/be: local keeper) — point at the bin dir.
: "${KEEPER_BIN:=$_BIN/keeper}"
: "${DOG_REMOTE_PATH:=$_BIN}"
: "${SUT:=loop}"                                  # loop | oneshot (oneshot scripts retired post-conversion)
# Loop-mode pre-flight (hoisted ABOVE any subshell): if the case targets the
# resident loop but be/main.js has not landed yet, SKIP the whole case cleanly
# (exit 0) here — a deferred SKIP inside the `( cd $JS && run_js )` subshell
# would only leave an empty JS capture and mis-report as a stdout FAIL.
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
: > "$TMP/$$/.be" 2>/dev/null || true
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sf "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
export WORK

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
pass()  { echo "PASS [$NAME]"; }

# --- normalisation: collapse the leading wall-clock date column -------
# Each hunk line begins with a `H:MM ` (or ` H:MM `) date column; two runs at
# different seconds differ ONLY there, so fold it to a constant `T `.  This is
# the ONLY normalisation — everything after (verb pad, uri, row order, blank
# lines, trailing newline) is compared byte-exact.  (Identical regex to the
# landed *case.sh oracles, so a divergence they would catch, this catches too.)
_norm() { sed -E 's/^ *[0-9]{1,2}:[0-9]{2} +/T /'; }

# --- the SUT selector: native cmd vs the JS path ----------------------
# run_native VERB ARGS…  — run native `be VERB ARGS` in $PWD.
run_native() { _v=$1; shift; "$BE" "$_v" "$@"; }

# run_js VERB ARGS…  — run the JS path for VERB in $PWD, per $SUT:
#   oneshot → jab be/<verb>.js ARGS         (the landed per-verb script)
#   loop    → jab be/main.js <verb> ARGS    (the JSQUE-002 resident loop)
# $SUT_JS, if set, overrides the resolved script path verbatim (one-shot shape)
# — used to point the harness at a deliberately-broken oracle for the FAIL proof.
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

# --- row probes (full-line byte-diff over wtlog/refs) -----------------
# _rows ULOG-PATH [VERB] — dump `<verb>\t<uri>` rows (optionally filtered).
# dumprows.js writes via io.log → fd 2, so fold stderr→stdout to capture the
# rows (else the row-diff compares two empty captures — a silent no-op).
_rows() { "$JABC" "$_CASE/../dumprows.js" "$1" "${2:-}" 2>&1; }

# _wtlog_rows DIR [VERB]  /  _refs_rows DIR — row probes for a worktree.
_wtlog_rows() { _rows "$1/.be/wtlog" "${2:-}"; }
_refs_rows() {
    _shard=$(ls -d "$1"/.be/*/ 2>/dev/null | grep -v '/\.be/\.' | head -1)
    [ -n "${_shard:-}" ] && [ -f "$_shard/refs" ] && _rows "$_shard/refs" || true
}

# --- the core assertion -----------------------------------------------
# assert_stdout NAT_OUT JS_OUT — strict full-line byte-diff of two captured
# stdouts after _norm.  This is the heart of the gate.
assert_stdout() {
    _norm <"$1" >"$1.norm"; _norm <"$2" >"$2.norm"
    cmp -s "$1.norm" "$2.norm" || {
        echo "--- native stdout ($1) ---"; cat "$1"
        echo "--- js stdout ($2) ---";     cat "$2"
        echo "--- diff (normalised) ---";  diff "$1.norm" "$2.norm" || true
        _fail "stdout differs (full-line byte-diff)"; }
}

# assert_wtlog NAT_DIR JS_DIR [VERB] — full-line byte-diff of wtlog rows.
assert_wtlog() {
    _wtlog_rows "$1" "${3:-}" >"$WORK/.nwt"; _wtlog_rows "$2" "${3:-}" >"$WORK/.jwt"
    cmp -s "$WORK/.nwt" "$WORK/.jwt" || {
        echo "--- native wtlog rows ---"; cat "$WORK/.nwt"
        echo "--- js wtlog rows ---";     cat "$WORK/.jwt"
        _fail "wtlog rows differ"; }
}

# assert_refs NAT_DIR JS_DIR — full-line byte-diff of project-shard refs rows.
assert_refs() {
    _refs_rows "$1" >"$WORK/.nrf"; _refs_rows "$2" >"$WORK/.jrf"
    cmp -s "$WORK/.nrf" "$WORK/.jrf" || {
        echo "--- native refs rows ---"; cat "$WORK/.nrf"
        echo "--- js refs rows ---";     cat "$WORK/.jrf"
        _fail "refs rows differ"; }
}

# --- baseline + per-side fork (mirrors putcase.sh) --------------------
# seed_baseline CMD — build a committed baseline in $WORK/base via $BE; $BASE set.
seed_baseline() {
    BASE="$WORK/base"; rm -rf "$BASE"; mkdir -p "$BASE"
    ( cd "$BASE" && mkdir .be && eval "$1" && "$BE" post 'base' >/dev/null 2>&1 )
}

# fork_pair — copy $BASE → native ($NAT) and JS ($JS) sides, re-anchoring each
# fork's row-0 at its OWN `.be` so the two stores don't collide (reanchor.js).
fork_pair() {
    NAT="$WORK/nat"; JS="$WORK/js"; rm -rf "$NAT" "$JS"
    cp -a "$BASE" "$NAT"; cp -a "$BASE" "$JS"
    "$JABC" "$_CASE/../../lib/reanchor.js" "$NAT"
    "$JABC" "$_CASE/../../lib/reanchor.js" "$JS"
}

# mutate CMD — apply CMD identically in both forks (cd'd into the wt).
mutate() { ( cd "$NAT" && eval "$1" ); ( cd "$JS" && eval "$1" ); }

# --- one-call verb parity over the fork pair --------------------------
# verb_parity VERB ARGS… — run native `be VERB ARGS` in $NAT and the JS path
# (per $SUT) in $JS, then assert stdout + wtlog-VERB rows + refs rows.  The
# single entry an in-place-verb case uses (put/delete/post/patch); flip $SUT
# to gate the loop instead of the script.
verb_parity() {
    _vp_verb=$1; shift
    ( cd "$NAT" && run_native "$_vp_verb" "$@" ) >"$NAT.out" 2>"$NAT.err" || true
    ( cd "$JS"  && run_js     "$_vp_verb" "$@" ) >"$JS.out"  2>"$JS.err"  || true
    assert_stdout "$NAT.out" "$JS.out"
    assert_wtlog  "$NAT" "$JS" "$_vp_verb"
    assert_refs   "$NAT" "$JS"
}

# --- clone-model parity (get): SUT clones the SAME remote into two dirs ---
# tree_eq A B — same CONTENT file set + same contents (excl `.be`/`.git`
# store/worktree metadata).  Borrowed from getcase.sh.
tree_eq() {
    _flt='^\./(\.be(/|$)|\.\.be\.idx$|\.git/)'
    _a=$(cd "$1" && find . -type f | grep -vE "$_flt" | sort)
    _b=$(cd "$2" && find . -type f | grep -vE "$_flt" | sort)
    [ "$_a" = "$_b" ] || { echo "--- A ---"; echo "$_a"; echo "--- B ---"; echo "$_b"; _fail "file set differs"; }
    for _f in $_a; do
        cmp -s "$1/$_f" "$2/$_f" || _fail "content differs: $_f"
    done
}

# clone_parity VERB REMOTE NAT_DIR JS_DIR — run native `be VERB REMOTE` into
# NAT_DIR and the JS path (per $SUT) into JS_DIR (both must pre-exist), then
# assert full-line stdout byte-parity + worktree-tree parity.  The single
# entry a clone-model case (get / dir fan-out) uses.  Leaves the captured
# stdouts at NAT_DIR.out / JS_DIR.out for the caller.
clone_parity() {
    _cp_verb=$1; _cp_remote=$2; _nd=$3; _jd=$4
    ( cd "$_nd" && run_native "$_cp_verb" "$_cp_remote" ) >"$_nd.out" 2>"$_nd.err" || true
    ( cd "$_jd" && run_js     "$_cp_verb" "$_cp_remote" ) >"$_jd.out" 2>"$_jd.err" || true
    assert_stdout "$_nd.out" "$_jd.out"
    tree_eq "$_nd" "$_jd"
}
