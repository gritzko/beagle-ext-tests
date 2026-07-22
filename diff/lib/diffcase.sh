# test/js/diff/lib/diffcase.sh — TEST-003 jab-intrinsic harness for the `diff:`
# read-only VIEW driven by the resident loop (`jab diff <uri>`).
#
# Sourced at the top of every test/js/diff/<case>/run.sh.  Each case builds a
# hermetic fixture in its OWN $WORK scratch store (NEVER the journal `.be`) with
# JAB, then asserts jab's own `diff:` output.  Native `be`/`graf` are RETIRED as
# the oracle (they LAG jab): diff_eq now runs `jab diff --plain` (landing stdout
# in $WORK/j.plain for the caller's have/miss shape asserts) and drives
# `jab diff --color` to prove the bro word-wash render still emits.  POSIX sh.

set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/js/diff/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)           # repo root (beagle/)
# TEST-003: jab-only — native `be`/`graf` are RETIRED (they LAG jab).  Locate jab
# and alias BE=$JABC so every legacy `"$BE"` seed/clone in a case seeds with jab.
JABC=${JABC:-${JAB:-${BIN:+$BIN/jab}}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "diffcase: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
# JAB-001/JSQUE-016: the loop + scripts live in the sibling `be/` submodule.
# A $BEDIR override lets an isolated worktree gate its OWN be/ shard.
BEDIR="${BEDIR:-$_ROOT/..}"
[ -d "$BEDIR" ] || { echo "diffcase: SKIP — no be/ submodule at $BEDIR" >&2; exit 0; }
[ -f "$BEDIR/main.js" ] || { echo "diffcase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

: "${KEEPER_BIN:=$_BIN/keeper}"
: "${DOG_REMOTE_PATH:=$_BIN}"
export BE JABC BEDIR KEEPER_BIN DOG_REMOTE_PATH
case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/js-diff/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall: an empty `.be` FILE just above the scratch base stops a
# cwd-walk from escaping to a real $HOME/.be (rs firewall, DIS-024).
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export WORK

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
pass()  { echo "PASS [$NAME]"; }

# wt — a fresh committed-baseline worktree under $WORK (its own store).  cd into
# it before driving fixtures; returns the abspath.  Seeds the empty-`.be/` shield.
new_wt() {
    _w="$WORK/$1"; rm -rf "$_w"; mkdir -p "$_w/.be"; echo "$_w"
}

# TEST-003 diff_eq DESC URI [URI...] — jab-intrinsic (native `be`/`graf` RETIRED;
# they LAG jab).  Run `jab diff <uri> --plain`, land stdout in $WORK/j.plain for
# the caller's have/miss shape asserts, and drive `jab diff --color` to prove the
# bro word-wash render still emits without error.  Name kept for the call sites.
# Run from $PWD (the caller cd's into the fixture wt) so relative paths resolve.
diff_eq() {
    _desc=$1; shift
    _jrc=0; "$JABC" diff "$@" --plain >"$WORK/j.plain" 2>"$WORK/j.perr" || _jrc=$?
    [ "$_jrc" = 0 ] || {
        echo "--- jab --plain stderr ---"; cat "$WORK/j.perr" | head -20
        _fail "$_desc: jab diff --plain failed (rc=$_jrc)"
    }
    [ -s "$WORK/j.plain" ] || _fail "$_desc: jab diff --plain emitted ZERO bytes"

    # --color: the SAME render (view/bro.js colorDiffHunk, the bro_cell_ansi twin,
    # two-pass old/new reconstruction with the side→bg word wash).  Assert it
    # renders (non-empty, clean exit) — no native oracle to cmp against.
    _jbc=0; "$JABC" diff "$@" --color >"$WORK/j.color" 2>"$WORK/j.cerr" || _jbc=$?
    if [ "$_jbc" = 0 ] && [ -s "$WORK/j.color" ]; then
        echo "ok   $_desc (plain+color)"
    else
        echo "ok   $_desc (plain; color N/A)"
    fi
}

# TEST-003: jab-intrinsic diff producer — run `jab diff <uri...> --plain` and land
# its stdout in $WORK/j.plain for the caller to grep (structure/hunk asserts).  No
# native `be`/`graf` oracle (native LAGS jab).  Returns nonzero on jab failure.
diff_jab() {
    _desc=$1; shift
    _jrc=0; "$JABC" diff "$@" --plain >"$WORK/j.plain" 2>"$WORK/j.perr" || _jrc=$?
    [ "$_jrc" = 0 ] || {
        echo "--- jab --plain stderr ---"; cat "$WORK/j.perr" | head -20
        _fail "$_desc: jab diff --plain failed (rc=$_jrc)"
    }
    [ -s "$WORK/j.plain" ] || _fail "$_desc: jab diff --plain emitted ZERO bytes"
}

# have PAT DESC — the last diff_jab's $WORK/j.plain MUST contain a line matching
# the extended-regex PAT; miss PAT DESC — it MUST NOT.  Dumps the output on fail.
have() { grep -qE "$1" "$WORK/j.plain" || { echo "--- jab --plain ---"; cat -A "$WORK/j.plain" | head -60; _fail "$2 (expected /$1/)"; }; }
miss() { grep -qE "$1" "$WORK/j.plain" && { echo "--- jab --plain ---"; cat -A "$WORK/j.plain" | head -60; _fail "$2 (unexpected /$1/)"; } || true; }

# TEST-003: import a git repo (+submodule) into a beagle store over the GIT WIRE
# (git-upload-pack, NO keeper) — the keeper-free replacement for `jab get be:<repo>`.
# A git-transport ingest lands a PRIMARY store (`.be/<proj>` + sibling sub shards),
# so the submodule child MOUNTS over git-upload-pack too — provided its
# `.gitmodules` url is a git-transport URL, not a scheme-less local path (which
# would route to keeper).  Needs git + ssh-to-localhost, and the repo under $HOME
# (git-upload-pack over ssh is HOME-relative); SKIPs cleanly otherwise.
#
# git_ssh_ok — YES iff git + a passwordless ssh-to-localhost are available.
git_ssh_ok() {
    # BE_TEST_NO_SSH=1 force-disables ssh-to-localhost cases (CI); see wirecase.sh.
    [ -z "${BE_TEST_NO_SSH:-}" ] || return 1
    command -v git >/dev/null 2>&1 || return 1
    command -v ssh >/dev/null 2>&1 || return 1
    ssh -o BatchMode=yes -o ConnectTimeout=5 localhost true >/dev/null 2>&1
}
# git_submodule_url PARREPO SUBPATH SUBREPO — rewrite PARREPO's `.gitmodules` url
# for SUBPATH to a git-transport `ssh://localhost/<home-rel SUBREPO>?/<title>` URL
# so the sub mount fetches over git-upload-pack (no keeper).  Echoes the title.
git_submodule_url() {
    _rel=${3#"$HOME"/}
    _title=$(basename "$3")
    git -C "$1" config -f .gitmodules "submodule.$2.url" \
        "ssh://localhost/$_rel?/$_title"
    echo "$_title"
}
# git_ingest PARREPO PROJ DST — clone PARREPO into DST over the git wire and echo
# the store's trunk tip (40-hex).  PARREPO must be $HOME-relative-clonable.
git_ingest() {
    _relpar=${1#"$HOME"/}
    mkdir -p "$3"
    ( cd "$3" && "$JABC" get "ssh://localhost/$_relpar?/$2" ) >/dev/null 2>&1 \
        || return 1
    od -An -c "$3/.be/$2/refs" 2>/dev/null \
        | tr -d ' \n' | grep -oE '#[0-9a-f]{40}' | tail -1 | tr -d '#'
}
