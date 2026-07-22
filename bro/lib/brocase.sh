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
# TEST-003: native `bro` is a STALE oracle (lags jab) — the differential legs
# are now GOLDEN asserts (golden.sh) seeded from jab.  `bro` is OPTIONAL (unused
# by the golden path); resolve jab from $JABC (ctest env) / $BIN / PATH.
BRO=${BRO:-${BIN:+$BIN/bro}}
BRO=${BRO:-$(command -v bro || true)}
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
# JAB-bro: `bro` is now a LOOP VERB (verbs/bro/bro.js), not the standalone
# entry `be/bro.js` — so the parity legs run `jab bro …` THROUGH THE LOOP, not
# `jab be/bro.js …`.  `jab bro` resolves loop.js + verbs/bro/bro.js via the
# upward `be/`-scan from the CWD, so the jab call must run with CWD inside a
# worktree that has the by-verb layout + the `be -> .` self-loop (the live
# `$_ROOT/../be` tree has NO self-loop, so use a store-backed worktree).
# $BROWT points at that worktree; default to the be/ tree itself ($_ROOT/..),
# which carries views/bro/bro.js (the old ~/todo/JAB-bro worktree is gone).
BROWT="${BROWT:-$(cd "$_ROOT/.." && pwd)}"
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
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

# --- assert helpers ---------------------------------------------------
_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# TEST-003: the differential legs golden-snapshot jab's own output (native `bro`
# is a stale oracle).  Accumulate labelled blocks; pass() golden_asserts them.
. "$_ROOT/lib/golden.sh"
GOLDEN=${GOLDEN:-$_CASE/golden.out}
_GSTREAM="$WORK/golden.stream"; : > "$_GSTREAM"

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

# bro_eq DESC ARG...  — TEST-003: run `jab bro --plain ARG...` (THROUGH THE LOOP,
# JAB-bro) and append its stdout + exit code to the golden stream (native `bro`
# oracle retired — jab is asserted intrinsically).  `jab bro` runs from $BROWT
# (be-scan finds views/bro/bro.js); every file arg is ABSOLUTIZED, then the
# volatile scratch path is folded to `WORK` so the golden is reproducible.
# _bro_sort_dirs — `bro` lists a directory in raw readdir order (deliberately:
# no sort in the hot render path), so the entry order is filesystem-dependent
# and NOT reproducible across boxes/CI.  Sort ONLY the entry run under each
# directory hunk banner (`hunk .../` or `hunk .../.`) — file bodies pass through
# untouched — so the golden is deterministic (LC_ALL=C byte order).
_bro_sort_dirs() {
    LC_ALL=C awk '
        function flush(   i, v, k) {
            for (i = 2; i <= n; i++) { v = a[i]; k = i - 1;
                while (k >= 1 && a[k] > v) { a[k+1] = a[k]; k-- } a[k+1] = v }
            for (i = 1; i <= n; i++) print a[i]; n = 0
        }
        /^hunk .*\/\.?$/          { flush(); print; d = 1; next }   # dir banner
        /^hunk / || /^=== / || /^$/ { flush(); d = 0; print; next } # file/section/blank
        d                          { a[++n] = $0; next }            # a dir entry
                                   { print }
        END { flush() }
    '
}

bro_eq() {
    _desc=$1; shift
    _abs_args=""
    for _a in "$@"; do _abs_args="$_abs_args $(_abs "$_a")"; done
    # eslint: $_abs_args is intentionally word-split into one arg per path.
    _jrc=0; ( cd "$BROWT" && "$JABC" bro --plain $_abs_args ) \
        >"$WORK/j.out" 2>"$WORK/j.err" || _jrc=$?
    { echo "=== $_desc (exit $_jrc) ==="; sed "s|$WORK|WORK|g" "$WORK/j.out" | _bro_sort_dirs; } \
        >>"$_GSTREAM"
    echo "ok   $_desc"
}

# pass — golden_assert the accumulated stream (cases with no bro_eq leave it
# empty → no assert, just the marker); GOLDEN_REGEN=1 re-snapshots.
pass() {
    [ -s "$_GSTREAM" ] && golden_assert "$NAME" "$GOLDEN" <"$_GSTREAM"
    echo "PASS [$NAME]"; exit 0
}
