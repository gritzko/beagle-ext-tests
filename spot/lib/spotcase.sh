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
_ROOT=$(cd "$_CASE/../.." && pwd)            # repo root (beagle/)
# TEST-003: jab-only — native `be` is RETIRED (it now LAGS jab).  Locate jab and
# alias BE=$JABC so the legacy `"$BE" post/get` seeds run jab; the search oracle
# is a committed golden of jab's OWN output (golden.sh), NOT native `be <scheme>`.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "spotcase: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
# JAB-001/JSQUE-016: the loop + handlers live in the sibling `be/` submodule.
# A $BEDIR override lets an isolated worktree gate its OWN be/ shard (JAB-021
# develops under ~/todo/JAB-021/be, not the landed beagle-ext).
BEDIR="${BEDIR:-$_ROOT/..}"
[ -d "$BEDIR" ] || { echo "spotcase: SKIP — no be/ submodule at $BEDIR" >&2; exit 0; }
[ -f "$BEDIR/main.js" ] || { echo "spotcase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }
# A case sets NEED_VERB to the handler it exercises (spot/grep/regex); the gate
# SKIPs until that worker's verbs/<verb>/<verb>.js exists (JAB-021/022/023 land
# their handlers independently).  Defaults to spot for the legacy search case.
: "${NEED_VERB:=spot}"
{ [ -f "$BEDIR/views/$NEED_VERB/$NEED_VERB.js" ] || [ -f "$BEDIR/verbs/$NEED_VERB/$NEED_VERB.js" ]; } || { echo "spotcase: SKIP — no $BEDIR/{views,verbs}/$NEED_VERB/$NEED_VERB.js yet" >&2; exit 0; }
[ -x "$JABC" ] || { echo "spotcase: no jab at $JABC" >&2; exit 2; }
BE=$JABC

: "${KEEPER_BIN:=$_BIN/keeper}"
: "${DOG_REMOTE_PATH:=$_BIN}"
export BE JABC BEDIR KEEPER_BIN DOG_REMOTE_PATH
case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/js-spot/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall: an empty `.be` FILE just above the scratch base stops a
# cwd-walk from escaping to a real $HOME/.be (rs firewall, DIS-024).
: > "$TMP/$$/.be" 2>/dev/null || true
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export WORK

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
pass()  { echo "PASS [$NAME]"; }

# new_wt NAME — a fresh empty-`.be/`-shielded worktree under $WORK (its own
# store).  cd into it before seeding fixtures; echoes the abspath.
new_wt() {
    _w="$WORK/$1"; rm -rf "$_w"; mkdir -p "$_w/.be"; echo "$_w"
}

# TEST-003 spot_eq DESC URI [TRAIL...] — jab-intrinsic STRUCTURE assert for a
# HIT search (native `be <scheme>` is RETIRED — it LAGS jab, no oracle cmp).
# Runs `jab <scheme> URI [TRAIL...]` and asserts jab's OWN hunk stream is
# well-formed: non-empty; EVERY banner line is `<verb> <file><ext>#L<n>` (the
# verb OUT of the scheme, the `.ext` gate honoured — only files matching the
# URI's `.ext` are searched); and, for grep, the literal needle appears in some
# body line.  TRAIL args are search trail tokens (`.ext` filter, `?ref`).  A
# stale queue from a prior crashed run is cleared (JSQUE-003 resume guard).
spot_eq() {
    _desc=$1; _uri=$2; shift 2
    _verb=${_uri%%:*}
    _ext=${_uri#*:}; _ext=${_ext%%#*}            # the `.ext` gate (e.g. `.c`)
    _needle=${_uri#*#}                            # the search body (after `#`)
    rm -f "$PWD/.be/queue" 2>/dev/null || true
    "$JABC" "$_verb" "$_uri" "$@" >"$WORK/j.out" 2>"$WORK/j.err" || {
        echo "--- jab stderr ($_uri $*) ---"; cat "$WORK/j.err" | head -20
        _fail "$_desc: jab $_verb exited non-zero"; }
    [ -s "$WORK/j.out" ] || { echo "--- jab stderr ---"; cat "$WORK/j.err" | head -20
        _fail "$_desc: expected hits but jab emitted ZERO bytes"; }
    #  Every banner line (`<verb> <path>#L<n>`) names the verb + an ext-matching
    #  file; body lines pass through.  Awk fails if any banner is malformed or a
    #  searched file violates the `.ext` gate.
    awk -v v="$_verb" -v ext="$_ext" '
        /#L[0-9]+$/ && $1==v && NF==2 {
            f=$2; sub(/#L[0-9]+$/,"",f);
            if (ext!="" && index(f, ext)!=length(f)-length(ext)+1) {
                print "BADEXT " f " (want *" ext ")" > "/dev/stderr"; bad=1 }
            seen=1; next }
        { }
        END { if (!seen) { print "NOBANNER" > "/dev/stderr"; exit 3 }
              if (bad) exit 4 }' "$WORK/j.out" 2>"$WORK/awk.err" || {
        echo "--- jab out ($_uri) ---"; cat -A "$WORK/j.out" | head -40
        echo "--- awk ---"; cat "$WORK/awk.err"
        _fail "$_desc: malformed banner / .ext gate violated"; }
    #  grep mode: the literal needle must appear in a body line (it is a literal
    #  substring search); regex/spot needles are patterns, not literals.
    if [ "$_verb" = grep ] && [ -n "$_needle" ]; then
        grep -Fq -- "$_needle" "$WORK/j.out" || {
            echo "--- jab out ($_uri) ---"; cat -A "$WORK/j.out" | head -40
            _fail "$_desc: grep hit body does not contain the literal needle '$_needle'"; }
    fi
    echo "ok   $_desc"
}

# TEST-003 spot_zero DESC URI — jab-intrinsic ZERO-HIT assert: `jab <scheme> URI`
# succeeds (exit 0) and emits NO hunks (empty stdout), the no-match contract.
spot_zero() {
    _desc=$1; _uri=$2; shift 2
    _verb=${_uri%%:*}
    rm -f "$PWD/.be/queue" 2>/dev/null || true
    _jrc=0; "$JABC" "$_verb" "$_uri" "$@" >"$WORK/j.out" 2>"$WORK/j.err" || _jrc=$?
    [ "$_jrc" = 0 ] || { echo "--- jab stderr ---"; cat "$WORK/j.err" | head -20
        _fail "$_desc: zero-hit search should exit 0, got $_jrc"; }
    [ -s "$WORK/j.out" ] && { echo "--- jab out ($_uri) ---"; cat -A "$WORK/j.out" | head -20
        _fail "$_desc: expected ZERO hits but jab emitted output"; }
    echo "ok   $_desc"
}

# spot_err DESC URI EXPECT — assert the loop FAILS (non-zero) and its stderr
# contains EXPECT, matching native's hint+exit (the `.ext` gate / no-body hint).
spot_err() {
    _desc=$1; _uri=$2; _expect=$3
    _verb=${_uri%%:*}
    rm -f "$PWD/.be/queue" 2>/dev/null || true
    _jrc=0; "$JABC" "$_verb" "$_uri" >"$WORK/j.out" 2>"$WORK/j.err" || _jrc=$?
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
