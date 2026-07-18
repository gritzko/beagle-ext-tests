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
# TEST-003: jab-only — native `be` is RETIRED (it now LAGS jab).  Locate jab and
# alias BE=$JABC so every legacy `"$BE"` seed/clone in a case seeds with jab too.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "patchcase: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
# JAB-001: scripts live in the sibling `be/` submodule ($_ROOT/../be).
# GUARD: skip (exit 0) if that cross-submodule path is absent.
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "patchcase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

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
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export WORK

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [$NAME]"; }

# TEST-003 jab-only DAG seeding.  `jab` here (a fresh primary in cwd, PWD=$ORG).
# The store's rolling `.keeper.idx` run indexes only the LATEST keeper, so an
# earlier commit's object (the t0 FORK POINT both branches need) reads MISSING
# after a 2nd post; drop the stale idx before each op to force a full re-index.
_jab() { rm -f .be/*.keeper.idx 2>/dev/null; "$BE" "$@"; }
# DIS-076: a bare post never moves a ref (uniform ruling) — the ONLY tip a
# worktree has is its own wtlog cur; ask jab (`refs` cur:), never grep .be/refs.
_orgtip() { ( cd "$1" && "$JABC" refs 2>/dev/null ) | sed -n 's/^cur: *//p'; }

# _boot MSG: FIRST commit on a fresh repo — post ALONE (put-before-post throws
# "Not a directory"); it auto-adds the wt.  Saves the trunk tip in $BOOT for a
# later trunk switch (bare `?` folds to the CURRENT branch, not trunk).
_boot() { _jab post "$1" >/dev/null 2>&1
          BOOT=$(_orgtip .); }
# _fork BR: label-only fork at cur (ABSOLUTE `?BR`, not `?./BR` which stores the
# branch literally as `./BR` and misses resolveRef).  Does NOT switch the wt.
_fork() { _jab put "?$1" >/dev/null 2>&1; }
# _sw BR: switch the wt to branch BR.  _trunk: switch back to trunk by PINNING
# the saved boot tip (`?#<t0>`), since a bare `?` re-resolves the current branch.
_sw() { _jab get "?$1" >/dev/null 2>&1; }
_trunk() { _jab get "?#$BOOT" >/dev/null 2>&1; }
# _ci MSG FILE...: stage the named files then commit on the current branch.
# DIS-076: a message-post only advances the WORKTREE — republish the current
# branch's own ref too (`post ?<branch>`, DIS-061's "standard advance"), since
# later builder steps (`_tip`, a `?branch` patch URI) read that ref.
_ci() {
    _msg=$1; shift
    _jab put "$@" >/dev/null 2>&1
    _jab post "$_msg" >/dev/null 2>&1
    _br=$(_orgbranch .); _jab post "?$_br" >/dev/null 2>&1
}
_orgbranch() { ( cd "$1" && "$JABC" refs 2>/dev/null ) | sed -n 's/^branch: *?//p'; }
# _tip BR: newest commit sha on branch BR (trunk = empty BR).  Exports nothing;
# callers assign (e.g. F1=$(_tip feat)).  DIS-076: every call site asks for the
# tip of the branch the wt is CURRENTLY attached to, right after committing
# onto it — a bare post no longer republishes that branch's ref (uniform
# ruling), so the wt's OWN cur (jab refs) is the only tip that is current.
_tip() { _orgtip .; }

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

# PATCH.mkd 2026-07-17: conflicts exit NON-ZERO loudly.  PATCH_EXPECT=conflict
# makes the runner REQUIRE a non-zero patch exit (markers/status/bytes still
# golden-asserted); unset keeps the legacy exit-0 requirement (compatible).
_run_patch() {  # _run_patch WTDIR URI
    _rp_rc=0
    ( cd "$1" && "$JABC" patch "$2" ) >"$WORK/js.out" 2>"$WORK/js.err" || _rp_rc=$?
    case "${PATCH_EXPECT:-}" in
        conflict) [ "$_rp_rc" -ne 0 ] \
            || _fail "conflict patch exited 0 — spec: NON-ZERO (PATCH.mkd 2026-07-17)" ;;
        *) [ "$_rp_rc" -eq 0 ] || _fail "JS patch failed: $(cat "$WORK/js.err")" ;;
    esac
}

# --- patch_parity: clone ONLY a JS worktree of $ORG, patch it, golden-assert --
# Usage:  patch_parity ORIGIN_BUILDER PATCH_URI [FILES...]
#   ORIGIN_BUILDER  builds the origin store in $ORG (a fresh primary repo,
#                   leaving cur at the branch we patch INTO).
#   PATCH_URI       the `be patch` arg (`#<sha>` | `?<br>`); a
#                   (PATCH.mkd 2026-07-17: URI bangs retired — no `?<br>!`.)
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
    #  TEST-003: drop the origin's stale keeper.idx so the clone sees EVERY commit
    #  (the rolling idx indexes only the latest keeper — the t0 fork point is hid).
    rm -f "$ORG"/.be/*.keeper.idx 2>/dev/null
    #  DIS-076: default clone = the WORKTREE, pinned at its OWN cur (no ref
    #  needed — a bare post never mints one).
    _ORGTIP=$(_orgtip "$ORG")
    JS="$WORK/js"; mkdir -p "$JS"
    ( cd "$JS"  && "$BE" get "file://$ORG/.be#$_ORGTIP" >/dev/null 2>&1 ) || _fail "JS clone failed"
    _run_patch "$JS" "$_uri"

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
      | sed -nE 's/^ *([0-9A-Za-z:]+ +)?([.xovXV!]{4}) +(.*)$/\2 \3/p'
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
    #  TEST-003: drop the origin's stale keeper.idx so the clone sees every commit.
    rm -f "$ORG"/.be/*.keeper.idx 2>/dev/null
    #  DIS-076: default clone = the WORKTREE, pinned at its OWN cur.
    _ORGTIP=$(_orgtip "$ORG")
    JS="$WORK/js"; mkdir -p "$JS"
    ( cd "$JS"  && "$BE" get "file://$ORG/.be#$_ORGTIP" >/dev/null 2>&1 ) || _fail "JS clone failed"
    _run_patch "$JS" "$_uri"

    #  JAB-003 fold jab stdout + the `patch` ULOG row + the merged FILE bytes
    #  into ONE stream, diffed vs the committed golden.
    {
        echo "=== stdout ==="; cat "$WORK/js.out"
        echo "=== patch row ==="; _patch_row "$JS"
        echo "=== file bytes ==="; _fbytes "$JS" "$_file"
    } | golden_assert "$NAME" "$GOLDEN"
}
