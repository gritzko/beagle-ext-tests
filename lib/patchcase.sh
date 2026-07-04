# JAB-003 test/js/lib/patchcase.sh — golden-snapshot harness for `bin/patch.js`
# (the pure-JS `be patch`, JS-052).  Sourced at the top of every
# test/js/patch/<case>/run.sh.  Each case builds ONE origin store with a
# trunk/feature divergence, clones ONLY a JS worktree, runs `jab patch <uri>`,
# then asserts its stdout + `patch` ULOG row + `jab status` + merged worktree
# bytes against a committed per-case golden (jab's own verified-correct
# snapshot).  No native `be patch` oracle: native stays columnar while jab
# emits true hunks, so jab-vs-be is retired (golden path: <case>/golden.out).
#
# Self-contained (does NOT source test/lib/case.sh — this case sits 3 levels
# deep at test/js/patch/<case>).  POSIX sh.

set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)              # test/js/patch/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)            # repo root
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "patchcase: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
# JAB-001: scripts live in the sibling `be/` submodule ($_ROOT/../be).
# GUARD: skip (exit 0) if that cross-submodule path is absent.
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "patchcase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }
[ -x "$JABC" ] || { echo "patchcase: no jab at $JABC" >&2; exit 2; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
export BE JABC PATCHJS

#  JS-052/DIS-051: pin the reproducible-build clock so the builder's `be post`
#  objects (and thus their shas, and the RGA/weave tie-break that decides the
#  conflict-fence SIDE ORDER) are stable run-to-run.  RONNow honours
#  SOURCE_DATE_EPOCH (abc/RON.c); jabc's ron.now() rides the same native path,
#  so the JS side pins identically.  Without it a conflict golden flips with
#  the wall-clock-driven commit shas (a TEST artifact, not a merge bug).
: "${SOURCE_DATE_EPOCH:=1467331200}"; export SOURCE_DATE_EPOCH   # 2016-07-01Z
: "${TZ:=UTC}"; export TZ

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
. "$_ROOT/lib/golden.sh"                          # JAB-003: golden_assert
GOLDEN=${GOLDEN:-$_CASE/golden.out}               # JAB-003: committed snapshot
WORK="$TMP/$$/js-patch/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export WORK

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [$NAME]"; }

# the last `patch` wtlog row, ts-normalised (store-backed wt: .be IS the wtlog).
_patch_row() {  # _patch_row WTDIR
    grep -a $'\tpatch\t' "$1/.be" 2>/dev/null | tail -1 | sed -E 's/^[^\t]*\t/T\t/'
}

# JAB-003 merged worktree bytes for the case FILES: label + content per file
# (a symlink shows its `-> target`, an exec blob its mode), snapshotting the
# WEAVE-merge result the golden captures verbatim.  Usage: _fbytes WTDIR FILES…
_fbytes() {
    _fb=$1; shift
    for f in "$@"; do
        printf -- '--- %s ---\n' "$f"
        if [ -L "$_fb/$f" ]; then printf -- '-> %s\n' "$(readlink "$_fb/$f")"
        elif [ -e "$_fb/$f" ]; then ls -l "$_fb/$f" | cut -c1-10; cat "$_fb/$f"; fi
    done
}

# --- patch_parity: clone ONLY a JS worktree of $ORG, patch it, golden-assert --
# Usage:  patch_parity ORIGIN_BUILDER PATCH_URI [FILES...]
#   ORIGIN_BUILDER  builds the origin store in $ORG (a fresh primary repo,
#                   leaving cur at the branch we patch INTO).
#   PATCH_URI       the `be patch` arg (`#<sha>` | `?<br>` | `?<br>!`); a
#                   literal `@F1` is expanded to the F1 sha the builder exports.
#   FILES           worktree files whose merged bytes go into the golden stream.
# Builder must `export F1=...` (etc.) for any `@NAME` refs in PATCH_URI.
patch_parity() {
    _builder=$1; _uri=$2; shift 2
    ORG="$WORK/org"; mkdir -p "$ORG/.be"
    #  Run the builder in THIS shell (cd in a saved-pwd block, not a subshell)
    #  so any `export F1=...` it does survives for the `@NAME` expansion below.
    _opwd=$(pwd); cd "$ORG"; "$_builder"; cd "$_opwd"
    #  Expand `@NAME` → the env var NAME the builder exported.
    case "$_uri" in
        *@*) _ref=$(printf '%s' "$_uri" | sed -E 's/.*@([A-Za-z0-9_]+).*/\1/')
             _val=$(eval "printf '%s' \"\${$_ref}\"")
             _uri=$(printf '%s' "$_uri" | sed "s/@$_ref/$_val/") ;;
    esac

    #  JAB-003 native oracle retired: clone ONLY the JS worktree, run jab patch.
    JS="$WORK/js"; mkdir -p "$JS"
    ( cd "$JS"  && "$BE" get "file://$ORG/.be?/org" >/dev/null 2>&1 ) || _fail "JS clone failed"
    ( cd "$JS" && "$JABC" patch "$_uri" ) >"$WORK/js.out" 2>"$WORK/js.err" \
        || _fail "JS patch failed: $(cat "$WORK/js.err")"

    #  JAB-003 fold jab stdout + the `patch` ULOG row + `jab status` buckets +
    #  the merged worktree bytes into ONE stream, diffed vs the committed golden.
    {
        echo "=== stdout ==="; cat "$WORK/js.out"
        echo "=== patch row ==="; _patch_row "$JS"
        echo "=== status ==="; _jstatus "$JS"
        echo "=== file bytes ==="; _fbytes "$JS" "$@"
    } | golden_assert "$NAME" "$GOLDEN"
}

# `jab status` of a wt, reduced to date-normalised `<bucket> <path>` rows (the
# header + summary stripped) — the JS-only restamp/classify golden (DIS-057).
_jstatus() {  # _jstatus WTDIR
    ( cd "$1" && "$JABC" status --plain 2>/dev/null ) \
      | sed -nE 's/^ *[0-9A-Za-z:]+ +([a-z]{3}) +(.*)$/\1 \2/p'
}

# JAB-003 patch_js_golden: JS-only path for the DOG-005 same-anchor residual.
# dog's symmetric WEAVEMerge orders the two conflict sides by the RGA commit-id
# tie-break (hash-order, ruled CORRECT); the clock is pinned (above) so the
# shas — and thus that side ORDER — are reproducible.  Native `be` retired as
# the oracle: snapshot jab's stdout + `patch` ULOG row + merged FILE bytes.
# Usage:  patch_js_golden ORIGIN_BUILDER PATCH_URI FILE
patch_js_golden() {
    _builder=$1; _uri=$2; _file=$3
    ORG="$WORK/org"; mkdir -p "$ORG/.be"
    _opwd=$(pwd); cd "$ORG"; "$_builder"; cd "$_opwd"
    case "$_uri" in
        *@*) _ref=$(printf '%s' "$_uri" | sed -E 's/.*@([A-Za-z0-9_]+).*/\1/')
             _val=$(eval "printf '%s' \"\${$_ref}\"")
             _uri=$(printf '%s' "$_uri" | sed "s/@$_ref/$_val/") ;;
    esac

    #  JAB-003 native oracle retired: clone ONLY the JS worktree, run jab patch.
    JS="$WORK/js"; mkdir -p "$JS"
    ( cd "$JS"  && "$BE" get "file://$ORG/.be?/org" >/dev/null 2>&1 ) || _fail "JS clone failed"
    ( cd "$JS" && "$JABC" patch "$_uri" ) >"$WORK/js.out" 2>"$WORK/js.err" \
        || _fail "JS patch failed: $(cat "$WORK/js.err")"

    #  JAB-003 fold jab stdout + the `patch` ULOG row + the merged FILE bytes
    #  into ONE stream, diffed vs the committed golden.
    {
        echo "=== stdout ==="; cat "$WORK/js.out"
        echo "=== patch row ==="; _patch_row "$JS"
        echo "=== file bytes ==="; _fbytes "$JS" "$_file"
    } | golden_assert "$NAME" "$GOLDEN"
}
