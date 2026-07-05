# test/js/ls/lib/lscase.sh — JAB-018 differential parity harness for the
# `ls:` / `lsr:` read-only worktree-listing VIEWs driven by the resident loop
# (`jab main.js <ls|lsr> <uri>`; the scheme is the verb).
#
# Sourced at the top of every test/js/ls/<case>/run.sh.  Each case builds a
# hermetic fixture in its OWN $WORK scratch store (NEVER the journal `.be`) with
# native `be`, then asserts the loop's `ls:`/`lsr:` output is BYTE-identical to
# native `be ls:<uri> --plain` (a single status hunk; `be` does not page it).
# POSIX sh; models test/js/diff/lib/diffcase.sh + test/js/bro/lib/brocase.sh.

set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/js/ls/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)           # repo root (beagle/)
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "lscase: cannot locate be (set BE= or BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-${JAB:-$_BIN/jab}}
# JAB-001/JSQUE-016: the loop + handlers live in the sibling `be/` submodule.
# A $BEDIR override lets an isolated worktree gate its OWN be/ shard (JAB-018
# develops under ~/todo/JAB-018/be, not the landed beagle-ext).
BEDIR="${BEDIR:-$_ROOT/..}"
[ -d "$BEDIR" ] || { echo "lscase: SKIP — no be/ submodule at $BEDIR" >&2; exit 0; }
[ -f "$BEDIR/main.js" ] || { echo "lscase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }
{ [ -f "$BEDIR/views/ls/ls.js" ] || [ -f "$BEDIR/verbs/ls/ls.js" ]; } || { echo "lscase: SKIP — no $BEDIR/{views,verbs}/ls/ls.js yet" >&2; exit 0; }
[ -x "$JABC" ] || { echo "lscase: no jab at $JABC" >&2; exit 2; }

: "${KEEPER_BIN:=$_BIN/keeper}"
: "${DOG_REMOTE_PATH:=$_BIN}"
export BE JABC BEDIR KEEPER_BIN DOG_REMOTE_PATH
case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/js-ls/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall: an empty `.be` FILE just above the scratch base stops a
# cwd-walk from escaping to a real $HOME/.be (rs firewall, DIS-024).
: > "$TMP/$$/.be" 2>/dev/null || true
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
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

# native_rel VERB DIR — native `be ls:DIR --plain` re-expressed RELATIVE to
# DIR: the DIR prefix stripped off each row's path column, the banner rewritten
# to the URI-014 `word URI` spell (`<verb>` at root, `<verb> <dir>` for a scope),
# blank lines dropped.  This is the per-hunk ORACLE for the relative-path
# listing: each hunk names its directory in the banner and lists entries BY NAME,
# so native ls: of that directory with the prefix stripped IS the expected hunk
# (root DIR="" strips nothing).  URI-014: native still bakes the `ls:` scheme
# banner (C follow-up); the JS view emits the word spell, so the oracle rewrites
# the banner to match (verb OUT of the scheme).
native_rel() {
    "$BE" "ls:$2" --plain 2>/dev/null | awk -v d="$2" -v verb="$1" '
        $0=="" { next }
        NR==1  { sub(/^ls:/, ""); print (($0=="") ? verb : verb " " $0); next }
        { head=substr($0,1,12); path=substr($0,13);
          if (d!="" && index(path,d)==1) path=substr(path,length(d)+1);
          print head path }'
}

# ls_rel DESC URI — assert `jab main.js <scheme> URI` (one hunk) matches the
# relative-rendered native ls: of URI's directory.  A stale queue from a prior
# crashed run is cleared so JSQUE-003 resume can't poison the next assertion.
ls_rel() {
    _desc=$1; _uri=$2
    _verb=${_uri%%:*}; _dir=${_uri#*:}
    rm -f "$PWD/.be/queue" 2>/dev/null || true
    native_rel "$_verb" "$_dir" > "$WORK/exp.out"
    _jrc=0; "$JABC" "$_verb" "$_uri" >"$WORK/j.out" 2>"$WORK/j.err" || _jrc=$?
    cmp -s "$WORK/exp.out" "$WORK/j.out" || {
        echo "--- expected (native ls: rel) ($_uri) ---"; cat -A "$WORK/exp.out" | head -60
        echo "--- jab loop ($_uri) ---";                  cat -A "$WORK/j.out"   | head -60
        echo "--- jab stderr ---";                        cat "$WORK/j.err"      | head -20
        echo "--- diff ---"; diff "$WORK/exp.out" "$WORK/j.out" | head -40 || true
        _fail "$_desc: stdout differs"
    }
    echo "ok   $_desc"
}

# ls_js DESC URI GOLDEN — JS-ONLY assertion (DIS-057 RULING 2026-06-29): assert
# `jab <scheme> URI` (one hunk) equals an EXPLICIT golden, NOT native ls:.  Used
# where the JS form deliberately DIVERGES from native — a staged RENAME lists as
# the `rmv`(src)+`mov`(dst) move PAIR (status's form), where native ls: still
# spells `mov src -> dst` + `new dst`.  GOLDEN is the date-NORMALISED expected
# body (date column collapsed to a literal `DATE` token so the assertion is
# clock-independent); the JS output is normalised the same way before compare.
_norm_dates() { sed -E 's/^( *)([0-9][0-9]:[0-9][0-9]|[0-9]{2}[A-Za-z]{3}[0-9]{2})/\1DATE/'; }
ls_js() {
    _desc=$1; _uri=$2; _golden=$3
    rm -f "$PWD/.be/queue" 2>/dev/null || true
    printf '%s\n' "$_golden" > "$WORK/exp.out"
    _jrc=0; "$JABC" "${_uri%%:*}" "$_uri" >"$WORK/j.raw" 2>"$WORK/j.err" || _jrc=$?
    _norm_dates < "$WORK/j.raw" > "$WORK/j.out"
    cmp -s "$WORK/exp.out" "$WORK/j.out" || {
        echo "--- expected (JS-only golden) ($_uri) ---"; cat -A "$WORK/exp.out" | head -60
        echo "--- jab loop ($_uri) ---";                  cat -A "$WORK/j.out"   | head -60
        echo "--- jab stderr ---";                        cat "$WORK/j.err"      | head -20
        echo "--- diff ---"; diff "$WORK/exp.out" "$WORK/j.out" | head -40 || true
        _fail "$_desc: stdout differs"
    }
    echo "ok   $_desc"
}

# lsr_js DESC URI GOLDEN — JS-ONLY lsr: assertion (date-normalised), for the same
# rename-pair divergence across the concatenated per-dir hunks.
lsr_js() {
    _desc=$1; _uri=$2; _golden=$3
    rm -f "$PWD/.be/queue" 2>/dev/null || true
    printf '%s\n' "$_golden" > "$WORK/exp.out"
    _jrc=0; "$JABC" lsr "$_uri" >"$WORK/j.raw" 2>"$WORK/j.err" || _jrc=$?
    _norm_dates < "$WORK/j.raw" > "$WORK/j.out"
    cmp -s "$WORK/exp.out" "$WORK/j.out" || {
        echo "--- expected (JS-only golden) ($_uri) ---"; cat -A "$WORK/exp.out" | head -80
        echo "--- jab lsr ($_uri) ---";                   cat -A "$WORK/j.out"   | head -80
        echo "--- jab stderr ---";                        cat "$WORK/j.err"      | head -20
        echo "--- diff ---"; diff "$WORK/exp.out" "$WORK/j.out" | head -40 || true
        _fail "$_desc: lsr hunks differ"
    }
    echo "ok   $_desc"
}

# lsr_mixed DESC URI ROOTGOLDEN -- DIR1 DIR2 ... — JS-ONLY lsr: assertion where
# only the ROOT hunk diverges from native (the rename pair); the named SUBDIR
# hunks still equal native ls: of that dir.  Expected = ROOTGOLDEN (the explicit,
# date-normalised root hunk) ++ each subdir's native_rel hunk (date-normalised);
# the JS lsr: output is date-normalised the same way.  DIR list pins the BFS
# recursion coverage + order after the root.
lsr_mixed() {
    _desc=$1; _uri=$2; _rootg=$3; shift 3
    [ "${1:-}" = "--" ] && shift
    { printf '%s\n' "$_rootg"
      for _d in "$@"; do native_rel lsr "$_d" | _norm_dates; done
    } > "$WORK/exp.out"
    rm -f "$PWD/.be/queue" 2>/dev/null || true
    _jrc=0; "$JABC" lsr "$_uri" >"$WORK/j.raw" 2>"$WORK/j.err" || _jrc=$?
    _norm_dates < "$WORK/j.raw" > "$WORK/j.out"
    cmp -s "$WORK/exp.out" "$WORK/j.out" || {
        echo "--- expected (root JS golden ++ native subdir hunks) ---"; cat -A "$WORK/exp.out" | head -80
        echo "--- jab lsr ($_uri) ---";                                 cat -A "$WORK/j.out"   | head -80
        echo "--- jab stderr ---";                                      cat "$WORK/j.err"      | head -20
        echo "--- diff ---"; diff "$WORK/exp.out" "$WORK/j.out" | head -40 || true
        _fail "$_desc: lsr hunks differ"
    }
    echo "ok   $_desc"
}

# lsr_rel DESC URI -- DIR1 DIR2 ... — assert `jab main.js lsr URI` matches the
# per-directory hunks (relative-rendered native ls: of each DIR, banner→lsr:),
# concatenated WITHOUT blank separators (the JS lsr: emits no gaps), in BFS
# directory order.  Each hunk is validated against native ls: of that
# directory; the DIR list pins the recursion COVERAGE + ORDER.  This is the
# WORK-QUEUE / per-directory design (NOT native lsr:'s monolithic hunk).
lsr_rel() {
    _desc=$1; _uri=$2; shift 2
    [ "${1:-}" = "--" ] && shift
    : > "$WORK/exp.out"
    for _d in "$@"; do native_rel lsr "$_d" >> "$WORK/exp.out"; done
    rm -f "$PWD/.be/queue" 2>/dev/null || true
    _jrc=0; "$JABC" lsr "$_uri" >"$WORK/j.out" 2>"$WORK/j.err" || _jrc=$?
    cmp -s "$WORK/exp.out" "$WORK/j.out" || {
        echo "--- expected (per-dir native ls: rel, lsr banner) ---"; cat -A "$WORK/exp.out" | head -80
        echo "--- jab lsr ($_uri) ---";                              cat -A "$WORK/j.out"   | head -80
        echo "--- jab stderr ---";                                   cat "$WORK/j.err"      | head -20
        echo "--- diff ---"; diff "$WORK/exp.out" "$WORK/j.out" | head -40 || true
        _fail "$_desc: lsr hunks differ"
    }
    echo "ok   $_desc"
}
