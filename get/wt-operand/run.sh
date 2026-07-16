#!/bin/sh
# test/get/wt-operand — DIS-062/DIS-063: `jab get //X` from a cell that is NOT
# inside X's tree.  Repro (gritzko, live): cd <empty cell under work/> && jab
# get //X used to land NOTHING in cwd — core/loop.js authorityRepo() consumed
# the `//X` authority on EVERY verb, rescoping the WHOLE run into X's own tree
# and refreshing X in place (a `get ?#<sha>` row appended to X's OWN wtlog,
# nothing checked out where the command was run).
#
# RED before the fix: DEST stays empty and srcwt's wtlog grows a row.
# GREEN after: DEST gets srcwt's checked-out tree (tracking `//srcwt#<chash>`)
# and srcwt's wtlog is BYTE-IDENTICAL to before the run.
#
# A REAL layout (per [/wiki/URI] step 1 + test/uri/resolvehash): ONE store,
# worktrees CLONE it (never bootstrap their own) — so `//srcwt` lives under
# the PROJECT ROOT's `work/` dir (test/bro/ticket's rs_work_root pattern) and
# is a SECONDARY anchor (a `.be` FILE redirecting to the shared store).  The
# clone step pins an explicit `#<sha>` fragment (resolvePin, no branch-ref
# lookup) — this repo's `post` no longer advances any branch ref (a separate,
# already-uncommitted change), so a bare `?branch` clone can't resolve here;
# pinning by hash sidesteps that unrelated gap entirely.  The empty destination
# cell sits alongside srcwt under the SAME work/ dir — NOT inside its tree.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/get/wt-operand
_ROOT=$(cd "$_CASE/../.." && pwd)                # test/
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "get/wt-operand: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "get/wt-operand: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/get/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# jab's upward be/-scan resolves the extension via this `jsrc` shard symlink.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true

# URI-016: bound the project-root climb ABOVE $PROJ (test/bro/ticket pattern) —
# ctest's own $BE_ROOT may sit much higher and see unrelated anchors.
export BE_ROOT="$WORK"

# the newest `#<40hex>` fragment in a wtlog dump (its curTip, test-side only —
# NOT a resolve_hash re-implementation, just an assertion/setup probe).
wtlog_tip() { od -An -c "$1" | tr -d ' \n' | grep -oE '#[0-9a-f]{40}' | tail -1 | tr -d '#'; }

# --- the scratch project: ONE store, worktrees CLONE it (never their own) --
PROJ="$WORK/proj"
mkdir -p "$PROJ/.be" "$PROJ/work"
printf 'readme\n' > "$PROJ/readme.txt"
( cd "$PROJ" && "$BE" post 'main tree' ) >/dev/null 2>&1 || _fail "could not seed the main tree"
MAIN_SHA=$(wtlog_tip "$PROJ/.be/wtlog")
[ -n "$MAIN_SHA" ] || _fail "no main-tree tip sha"

# srcwt = //srcwt = $PROJ/work/srcwt — a CLONE of the shared store (pinned by
# hash, sidestepping the unrelated branch-ref gap), then advanced with its OWN
# commit so its tip differs from the main tree's.
SRC="$PROJ/work/srcwt"
mkdir -p "$SRC"
( cd "$SRC" && "$JABC" get "file:$PROJ/.be#$MAIN_SHA" ) >/dev/null 2>&1 \
    || _fail "could not clone srcwt"
printf 'ticket work\n' > "$SRC/ticket.txt"
( cd "$SRC" && "$JABC" put ticket.txt && "$JABC" post 'ticket work' ) >/dev/null 2>&1 \
    || _fail "could not advance srcwt"

# snapshot srcwt's wtlog BEFORE the repro'd get — the untouched-source assert.
cp "$SRC/.be" "$WORK/srcwt.be.before"

# an EMPTY cell, sibling of srcwt under the SAME work/ dir — NOT inside its
# tree, so `//srcwt` on arg0 must be an OPERAND, not the run's context.
DEST="$PROJ/work/dest"
mkdir -p "$DEST"

RC=0
( cd "$DEST" && "$JABC" get "//srcwt" ) >"$WORK/get.out" 2>"$WORK/get.err" || RC=$?
[ "$RC" = 0 ] || { cat "$WORK/get.err" >&2; _fail "jab get //srcwt exit=$RC"; }

# --- assert: the clone landed in cwd (DEST), at srcwt's rev ----------------
[ -f "$DEST/readme.txt" ] || _fail "DEST missing readme.txt (main-tree content) — nothing cloned into cwd"
[ -f "$DEST/ticket.txt" ] || _fail "DEST missing ticket.txt (srcwt's own commit) — nothing cloned into cwd"
[ "$(cat "$DEST/ticket.txt")" = "ticket work" ] || _fail "DEST/ticket.txt has the wrong content"
[ -e "$DEST/.be" ] || _fail "DEST has no .be anchor — no clone landed"

# --- assert: srcwt (the SOURCE) is UNTOUCHED — no row appended -------------
cmp -s "$SRC/.be" "$WORK/srcwt.be.before" \
    || _fail "srcwt's wtlog CHANGED — the run rescoped INTO srcwt and refreshed it in place (the DIS-062 bug)"

# --- assert: DEST tracks `//srcwt` at srcwt's OWN rev, not the main tree ---
SRCWT_TIP=$(wtlog_tip "$SRC/.be")
[ -n "$SRCWT_TIP" ] || _fail "no srcwt tip sha"
od -An -c "$DEST/.be" | tr -d ' \n' | grep -q "//srcwt#$SRCWT_TIP" \
    || _fail "DEST's wtlog does not track //srcwt#$SRCWT_TIP"

echo "PASS [$NAME]"
