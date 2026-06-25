# test/js/bro/lib/brocase.sh — differential parity harness for `bin/bro.js`
# (the pure-JS file/dir viewer, JS-053 TODO#2).  Sourced at the top of every
# test/js/bro/<case>/run.sh.  Renders the SAME URI args with native `bro --plain`
# AND `jabc bin/bro.js --plain`, then asserts the two STDOUT streams are
# byte-identical (the BROPlain `!BRO_COLOR` path: banner + verbatim text / dir
# listing).  Self-contained POSIX sh; no native `be` needed — bro reads the FS.

set -eu

# --- locate binaries + the bro.js extension ---------------------------
_CASE=$(cd "$(dirname "$0")" && pwd)            # test/js/bro/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)          # repo root
# The native `bro` oracle: prefer $BIN (DOG_BIN_DIR under ctest), else PATH.
BRO=${BRO:-${BIN:+$BIN/bro}}
BRO=${BRO:-$(command -v bro || true)}
[ -n "$BRO" ] && [ -x "$BRO" ] || { echo "brocase: cannot locate bro (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BRO")
JABC=${JABC:-$_BIN/jab}
# JAB-bro: `bro` is now a LOOP VERB (verbs/bro/bro.js), not the standalone
# entry `be/bro.js` — so the parity legs run `jab bro …` THROUGH THE LOOP, not
# `jab be/bro.js …`.  `jab bro` resolves loop.js + verbs/bro/bro.js via the
# upward `be/`-scan from the CWD, so the jab call must run with CWD inside a
# worktree that has the by-verb layout + the `be -> .` self-loop (the live
# `$_ROOT/../be` tree has NO self-loop, so use a store-backed worktree).
# $BROWT points at that worktree; default to the JAB-bro checkout.
BROWT="${BROWT:-$HOME/todo/JAB-bro}"
# GUARD: skip (exit 0) if the worktree has no bro verb handler (not yet landed).
{ [ -f "$BROWT/views/bro/bro.js" ] || [ -f "$BROWT/verbs/bro/bro.js" ]; } || {
    echo "brocase: SKIP — no bro handler at $BROWT/{views,verbs}/bro/bro.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "brocase: no jab at $JABC" >&2; exit 2; }
export BRO JABC BROWT
# A separate-process extension run; silence the JSC singleton leak (parity is
# the assertion, not allocator hygiene).
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/js-bro/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
export WORK
# Native `bro` resolves a dog HOME by walking cwd up for a `.be` anchor (theme /
# keeper); under /tmp with none it aborts NOHOME.  Plant an empty `.be` dir at
# the case root so the walk anchors here, and a `.be` FILE just ABOVE the scratch
# to firewall the walk from escaping to a real $HOME/.be (the repo-setup pattern).
mkdir -p "$WORK/.be"
: > "$TMP/$$/.be" 2>/dev/null || true

# --- assert helpers ---------------------------------------------------
_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# _abs ARG  — echo a path arg absolutized against the CALLER's cwd, preserving a
# trailing `/` and a `#fragment` (so `a.c#main`, `src/`, `/abs/x` all map right).
# `jab bro` runs from the WORKTREE cwd (for the verb scan), so every file arg must
# be absolute or native `bro` (caller cwd) and `jab bro` (worktree cwd) would view
# different files.  A `#frag` rides the banner — split it off, absolutize the path,
# re-attach.  An already-absolute path is echoed unchanged.
_abs() {
    case $1 in
        *#*) _p=${1%%#*}; _f="#${1#*#}" ;;
        *)   _p=$1;       _f="" ;;
    esac
    case $_p in
        /*) printf '%s%s\n' "$_p" "$_f" ;;
        *)  printf '%s/%s%s\n' "$(pwd)" "$_p" "$_f" ;;
    esac
}

# bro_eq DESC ARG...  — native `bro --plain ARG...` vs `jab bro --plain ARG...`
# (THROUGH THE LOOP, JAB-bro); the two STDOUT streams must be byte-identical.
# `jab bro` runs from $BROWT (so the be-scan finds verbs/bro/bro.js); native
# runs from the caller's cwd.  Every file arg is ABSOLUTIZED (against the
# CALLER's cwd) and passed to BOTH legs — so they view the SAME files AND emit
# the SAME `hunk <uri>` banner (the banner echoes the arg verbatim, so a
# relative-vs-absolute arg would diverge the banner).  The exit code is
# asserted only as zero/non-zero (the oracle's dog-CLI FILENONE code is not
# reproducible from a JS handler — a throw maps to exit 1).
bro_eq() {
    _desc=$1; shift
    # Absolutize every file arg (against the CALLER's cwd) — used by BOTH legs.
    _abs_args=""
    for _a in "$@"; do _abs_args="$_abs_args $(_abs "$_a")"; done
    # `|| _rc=$?` keeps a non-zero exit (a missing-URI case) from tripping set -e.
    # eslint: $_abs_args is intentionally word-split into one arg per path.
    _orc=0; "$BRO" --plain $_abs_args >"$WORK/o.out" 2>"$WORK/o.err" || _orc=$?
    _jrc=0; ( cd "$BROWT" && "$JABC" bro --plain $_abs_args ) \
        >"$WORK/j.out" 2>"$WORK/j.err" || _jrc=$?
    cmp -s "$WORK/o.out" "$WORK/j.out" || {
        echo "--- oracle ---";  cat -A "$WORK/o.out" | head -40
        echo "--- jab bro ---"; cat -A "$WORK/j.out" | head -40
        _fail "$_desc: stdout differs"
    }
    # exit-code class must agree (both clean, or both fail).
    { [ "$_orc" = 0 ] && [ "$_jrc" = 0 ]; } || { [ "$_orc" != 0 ] && [ "$_jrc" != 0 ]; } || \
        _fail "$_desc: exit class differs (oracle=$_orc js=$_jrc)"
    echo "ok   $_desc"
}

pass() { echo "PASS [$NAME]"; exit 0; }
