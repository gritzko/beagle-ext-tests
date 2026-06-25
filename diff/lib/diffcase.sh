# test/js/diff/lib/diffcase.sh — JAB-014 differential parity harness for the
# `diff:` read-only VIEW driven by the resident loop (`jab main.js diff <uri>`).
#
# Sourced at the top of every test/js/diff/<case>/run.sh.  Each case builds a
# hermetic fixture in its OWN $WORK scratch store (NEVER the journal `.be`) with
# native `be`, then asserts the loop's `diff:` output is BYTE-identical to the
# native dog producer:
#   --plain : oracle is native `be <uri> --plain` (line-based unified diff; `be`
#             does NOT page a --plain diff, so it equals graf's direct output).
#   --color : oracle is native `graf <uri> --color` (the DIRECT dog producer, the
#             SAME HUNK `.color` cursor the JS loop drives).  `be --color` pipes
#             through bro (the pager) and is a DIFFERENT, richer render — not the
#             producer-level parity JAB-014 targets.
# POSIX sh; models test/js/lib/parity.sh + test/js/bro/lib/brocase.sh.

set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/js/diff/<case>
_ROOT=$(cd "$_CASE/../../../.." && pwd)           # repo root (beagle/)
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "diffcase: cannot locate be (set BE= or BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
GRAF=${GRAF:-$_BIN/graf}
JABC=${JABC:-${JAB:-$_BIN/jab}}
# JAB-001/JSQUE-016: the loop + scripts live in the sibling `be/` submodule.
# A $BEDIR override lets an isolated worktree gate its OWN be/ shard.
BEDIR="${BEDIR:-$_ROOT/../be}"
[ -d "$BEDIR" ] || { echo "diffcase: SKIP — no be/ submodule at $BEDIR" >&2; exit 0; }
[ -f "$BEDIR/main.js" ] || { echo "diffcase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }
[ -x "$JABC" ] || { echo "diffcase: no jab at $JABC" >&2; exit 2; }
[ -x "$GRAF" ] || { echo "diffcase: no graf at $GRAF" >&2; exit 2; }

: "${KEEPER_BIN:=$_BIN/keeper}"
: "${DOG_REMOTE_PATH:=$_BIN}"
export BE GRAF JABC BEDIR KEEPER_BIN DOG_REMOTE_PATH
case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/test/lib/repo-setup.sh"
WORK="$TMP/$$/js-diff/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall: an empty `.be` FILE just above the scratch base stops a
# cwd-walk from escaping to a real $HOME/.be (rs firewall, DIS-024).
: > "$TMP/$$/.be" 2>/dev/null || true
export WORK

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
pass()  { echo "PASS [$NAME]"; }

# wt — a fresh committed-baseline worktree under $WORK (its own store).  cd into
# it before driving fixtures; returns the abspath.  Seeds the empty-`.be/` shield.
new_wt() {
    _w="$WORK/$1"; rm -rf "$_w"; mkdir -p "$_w/.be"; echo "$_w"
}

# diff_eq DESC URI [URI...] — assert the loop's `diff:` matches the native dog
# producer for both --plain (oracle: `be`) and --color (oracle: `graf`).  Run
# from $PWD (the caller cd's into the fixture wt) so relative paths resolve the
# same.  The leading args are the diff URI(s); a `diff:a/ b/` multi-root case
# passes two URI tokens.
diff_eq() {
    _desc=$1; shift
    # --plain: native be vs the loop.
    _orc=0; "$BE" "$@" --plain   >"$WORK/o.plain" 2>"$WORK/o.perr" || _orc=$?
    _jrc=0; "$JABC" "$BEDIR/main.js" diff "$@" --plain \
                                     >"$WORK/j.plain" 2>"$WORK/j.perr" || _jrc=$?
    cmp -s "$WORK/o.plain" "$WORK/j.plain" || {
        echo "--- be --plain ---";   cat -A "$WORK/o.plain" | head -60
        echo "--- jab --plain ---";  cat -A "$WORK/j.plain" | head -60
        echo "--- diff ---"; diff "$WORK/o.plain" "$WORK/j.plain" | head -40 || true
        _fail "$_desc: --plain stdout differs"
    }
    { [ "$_orc" = 0 ] && [ "$_jrc" = 0 ]; } || { [ "$_orc" != 0 ] && [ "$_jrc" != 0 ]; } || \
        _fail "$_desc: --plain exit class differs (be=$_orc jab=$_jrc)"

    # --color: native graf is the DIRECT producer (the same HUNK `.color`
    # cursor the loop drives) — BUT graf has no `--at` baseline, so a
    # wt-vs-base form (`diff:` / `diff:<file>` with no range) errors GRAFNOAT
    # there (only `be` composes the baseline, and `be --color` pages via bro, a
    # different render).  When graf can't produce the color oracle, the --plain
    # leg (oracle `be`) already gates the case; skip the --color assert.
    _ogc=0; "$GRAF" "$@" --color >"$WORK/o.color" 2>"$WORK/o.cerr" || _ogc=$?
    if [ "$_ogc" = 0 ] && [ -s "$WORK/o.color" ]; then
        "$JABC" "$BEDIR/main.js" diff "$@" --color \
                                     >"$WORK/j.color" 2>"$WORK/j.cerr" || true
        cmp -s "$WORK/o.color" "$WORK/j.color" || {
            echo "--- graf --color ---";  cat -v "$WORK/o.color" | head -60
            echo "--- jab --color ---";   cat -v "$WORK/j.color" | head -60
            _fail "$_desc: --color stdout differs"
        }
        echo "ok   $_desc (plain+color)"
    else
        echo "ok   $_desc (plain; color N/A — graf has no --at baseline)"
    fi
}
