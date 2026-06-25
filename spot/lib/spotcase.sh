# test/js/spot/lib/spotcase.sh — JAB-021/022/023 differential parity harness
# for the `spot:` / `grep:` / `regex:` search VIEWs driven by the resident loop
# (`jab main.js <spot|grep|regex> <uri>`; the scheme is the verb).  Pure JS over
# tok + classify + the abc.index u64 lane + emit; the handler spawns NO dog
# binary and reads NO /proc.
#
# Sourced at the top of every test/js/spot/<case>/run.sh.  Each case builds a
# hermetic fixture in its OWN $WORK scratch store (NEVER the journal `.be`) with
# native `be`, then asserts the loop's search output is BYTE-identical to native
# `be <scheme>:<uri> --plain` (the spot dog's plain hunk stream).
# POSIX sh; models test/js/ls/lib/lscase.sh.
#
# PARITY CAVEAT (JAB-021): the `path#func:Lnn` URI's `#func` segment needs the
# tok DEF pass (S->N retag), which has NO JS binding (tok.parse = TOKLexer only).
# Cases that assert byte-parity therefore use needles whose context window
# starts at file top (no enclosing DEF before it) so native ALSO emits no #func
# — the `#func`-dependent rows are a separate MUST-ASK (see the ticket).  The
# `spot_eq` helper takes the URI/body/ext; `spot_err` checks the stderr+exit.

set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)              # test/js/spot/<case>
_ROOT=$(cd "$_CASE/../../../.." && pwd)            # repo root (beagle/)
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "spotcase: cannot locate be (set BE= or BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-${JAB:-$_BIN/jab}}
# JAB-001/JSQUE-016: the loop + handlers live in the sibling `be/` submodule.
# A $BEDIR override lets an isolated worktree gate its OWN be/ shard (JAB-021
# develops under ~/todo/JAB-021/be, not the landed beagle-ext).
BEDIR="${BEDIR:-$_ROOT/../be}"
[ -d "$BEDIR" ] || { echo "spotcase: SKIP — no be/ submodule at $BEDIR" >&2; exit 0; }
[ -f "$BEDIR/main.js" ] || { echo "spotcase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }
# A case sets NEED_VERB to the handler it exercises (spot/grep/regex); the gate
# SKIPs until that worker's verbs/<verb>/<verb>.js exists (JAB-021/022/023 land
# their handlers independently).  Defaults to spot for the legacy search case.
: "${NEED_VERB:=spot}"
{ [ -f "$BEDIR/views/$NEED_VERB/$NEED_VERB.js" ] || [ -f "$BEDIR/verbs/$NEED_VERB/$NEED_VERB.js" ]; } || { echo "spotcase: SKIP — no $BEDIR/{views,verbs}/$NEED_VERB/$NEED_VERB.js yet" >&2; exit 0; }
[ -x "$JABC" ] || { echo "spotcase: no jab at $JABC" >&2; exit 2; }

: "${KEEPER_BIN:=$_BIN/keeper}"
: "${DOG_REMOTE_PATH:=$_BIN}"
export BE JABC BEDIR KEEPER_BIN DOG_REMOTE_PATH
case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/test/lib/repo-setup.sh"
WORK="$TMP/$$/js-spot/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall: an empty `.be` FILE just above the scratch base stops a
# cwd-walk from escaping to a real $HOME/.be (rs firewall, DIS-024).
: > "$TMP/$$/.be" 2>/dev/null || true
export WORK

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
pass()  { echo "PASS [$NAME]"; }

# new_wt NAME — a fresh empty-`.be/`-shielded worktree under $WORK (its own
# store).  cd into it before seeding fixtures; echoes the abspath.
new_wt() {
    _w="$WORK/$1"; rm -rf "$_w"; mkdir -p "$_w/.be"; echo "$_w"
}

# spot_eq DESC URI [TRAIL...] — assert `jab main.js <scheme> URI [TRAIL...]`
# matches native `be <URI> [TRAIL...] --plain` byte-for-byte.  TRAIL args are
# the native trail tokens (a `.ext` filter, a `?ref` historic selector).  A
# stale queue from a prior crashed run is cleared so JSQUE-003 resume can't
# poison the next assertion.
spot_eq() {
    _desc=$1; _uri=$2; shift 2
    _verb=${_uri%%:*}
    rm -f "$PWD/.be/queue" 2>/dev/null || true
    #  The search VIEW names each hunk banner by its VERB (`grep <uri>` /
    #  `spot <uri>` / `regex <uri>`), not native's generic `hunk <uri>` — so
    #  rewrite the native oracle's banner label to the verb before the compare
    #  (mirrors lscase's banner-scheme rewrite).  Only the `hunk <uri>` header
    #  lines are touched; body lines pass through verbatim.
    "$BE" "$_uri" "$@" --plain 2>"$WORK/exp.err" \
      | awk -v v="$_verb" '$1=="hunk" && NF==2 && $2 ~ /#L[0-9]+/ {$1=v} {print}' \
      > "$WORK/exp.out" || true
    _jrc=0; "$JABC" "$BEDIR/main.js" "$_verb" "$_uri" "$@" >"$WORK/j.out" 2>"$WORK/j.err" || _jrc=$?
    cmp -s "$WORK/exp.out" "$WORK/j.out" || {
        echo "--- expected (native $_verb: --plain) ($_uri $*) ---"; cat -A "$WORK/exp.out" | head -60
        echo "--- jab loop ($_uri $*) ---";                          cat -A "$WORK/j.out"   | head -60
        echo "--- jab stderr ---";                                   cat "$WORK/j.err"      | head -20
        echo "--- diff ---"; diff "$WORK/exp.out" "$WORK/j.out" | head -40 || true
        _fail "$_desc: stdout differs"
    }
    echo "ok   $_desc"
}

# spot_err DESC URI EXPECT — assert the loop FAILS (non-zero) and its stderr
# contains EXPECT, matching native's hint+exit (the `.ext` gate / no-body hint).
spot_err() {
    _desc=$1; _uri=$2; _expect=$3
    _verb=${_uri%%:*}
    rm -f "$PWD/.be/queue" 2>/dev/null || true
    _jrc=0; "$JABC" "$BEDIR/main.js" "$_verb" "$_uri" >"$WORK/j.out" 2>"$WORK/j.err" || _jrc=$?
    [ "$_jrc" -ne 0 ] || {
        echo "--- jab stdout ---"; cat -A "$WORK/j.out" | head -20
        echo "--- jab stderr ---"; cat "$WORK/j.err" | head -20
        _fail "$_desc: expected non-zero exit, got 0"
    }
    grep -q -- "$_expect" "$WORK/j.err" || {
        echo "--- jab stderr (want '$_expect') ---"; cat "$WORK/j.err" | head -20
        _fail "$_desc: stderr missing '$_expect'"
    }
    echo "ok   $_desc"
}
