#!/bin/sh
# test/uri/resolvehash — URI-016: the ONE URI->hash resolver, per [/wiki/URI]
# §URI->hash resolution.  Seeds a scratch project (root = meta/ + .be, a
# work/WT worktree, a nested sub inside it), then asserts resolve_hash()'s
# 9-field record field-by-field: the 6 numbered steps, the submodule descent
# (spath/shard re-anchor), the whole step-5 ladder, and the refusal codes.
#
# RED before core/resolve_hash.js exists (no resolver at all — every URI->hash
# site re-derived its own half); GREEN after.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/uri/resolvehash
_ROOT=$(cd "$_CASE/../.." && pwd)                # test/
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "resolvehash: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "resolvehash: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/uri/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# DIS-076: hermetic jsrc — without this, jab's upward scan escapes past $TMP
# to a stray $HOME/jsrc (a DIFFERENT, unrelated tree) instead of THIS worktree.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# each tree's OWN tip (its wtlog's last get/post) — step 5.5's oracle.  NOT
# put/tipsha.js: that reads the shard TRUNK, identical for all three here.
tipsha() { "$JABC" "$_CASE/curtip.js" "$1"; }

# --- the scratch project -------------------------------------------------
# A REAL layout: ONE store with a NAMED shard, and the wts are CLONES of it
# ([/meta/work] §Typical CLI commands) — NOT each bootstrapping its own store.
# That is what [/wiki/URI] step 1 describes: one `store` per project, many
# shards under it, so store/shard composes for every tree in the project.
# `.be/alpha` pre-created => the bootstrap shards the store as `alpha`.
PROJ="$WORK/proj"
mkdir -p "$PROJ/meta" "$PROJ/.be/alpha"
printf 'readme\n' > "$PROJ/README.mkd"
( cd "$PROJ" && "$BE" post 'main tree' ) >/dev/null 2>&1 || _fail "could not seed the main tree"
# DIS-076: a bare post never mints a ref — pin the clone URI at the tip sha
# (the proven pattern: `file://<src>/.be#<sha>`, no trunk ref needed).
M0=$(tipsha "$PROJ")
[ -n "$M0" ] || _fail "could not resolve the main tree's tip"

# the worktree `//WT` = $PROJ/work/WT: a CLONE of the project store's `alpha`.
WT="$PROJ/work/WT"
mkdir -p "$WT"
( cd "$WT" && "$BE" get "file:$PROJ/.be?/alpha#$M0" ) >/dev/null 2>&1 || _fail "could not clone the worktree"

# A nested sub INSIDE the wt, kept BEHIND its recorded pin — the case the
# trailing-slash convention exists for.  The sub's clone stays at the main
# tree's commit (de-facto) while the wt PINS it at the wt's later commit
# (de-jure), so the two readings cannot coincide by accident.
SUB="$WT/sub"
mkdir -p "$SUB"
( cd "$SUB" && "$BE" get "file:$PROJ/.be?/alpha#$M0" ) >/dev/null 2>&1 || _fail "could not clone the sub"

# the wt advances (put stages: a CLONE has a base, so post does not auto-add).
mkdir -p "$WT/dir"
printf 'main\n' > "$WT/main.js"
printf 'deep\n' > "$WT/dir/deep.txt"
( cd "$WT" && "$BE" put main.js dir/deep.txt && "$BE" post 'wt' ) >/dev/null 2>&1 \
    || _fail "could not seed the worktree"
PIN=$(tipsha "$WT")           # the wt's commit — what the sub gets pinned AT

# Record the gitlink.  jab has NO CLI spelling for a manual pin (`jab put
# sub#<sha>` is PUTNONE — a move dest), so the row goes into the wtlog and the
# next post folds it into a 160000 tree entry.  Same procedure as test/sub/lib.
. "$_ROOT/sub/lib/subcase.sh" 2>/dev/null || true
sc_pin_gitlink "sub" "$WT/.be" "$PIN"
( cd "$WT" && "$BE" post 'pin sub' ) >/dev/null 2>&1 || _fail "could not fold the gitlink"
# DIS-076: a bare post never advances a ref — publish trunk explicitly so
# step 5.3's reflog read reproduces the wt's current tip.
( cd "$WT" && "$BE" post '?' ) >/dev/null 2>&1 || _fail "could not publish trunk"

# --- the tips the record must reproduce ----------------------------------
MAIN_SHA=$(tipsha "$PROJ");  WT_SHA=$(tipsha "$WT");  SUB_SHA=$(tipsha "$SUB")
# PIN (de-jure, the wt's tree) vs SUB_SHA (de-facto, the sub's own wtlog).
# the sub is pinned at the main tree's commit; the wt has moved past it.
for _v in "$MAIN_SHA" "$WT_SHA" "$SUB_SHA"; do
    case "$_v" in *[!0-9a-f]*|"") _fail "tip sha not 40-hex: '$_v'" ;; esac
done
[ "$PIN" != "$SUB_SHA" ] || _fail "fixture: the pin must DIFFER from the sub's checkout"

# Run from INSIDE the wt so srcRoot()/project.root() infer the scratch project.
export PROJ MAIN_SHA WT_SHA SUB_SHA PIN BEDIR
export ROOT="$_ROOT"
( cd "$WT" && "$JABC" "$_CASE/check.js" ) || _fail "the record does not match the spec"

echo "PASS [$NAME]"
