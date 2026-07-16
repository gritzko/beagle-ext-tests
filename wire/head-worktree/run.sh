#!/bin/sh
# DIS-062 test/wire/head-worktree — `head //X` against ANOTHER LOCAL worktree.
# Two worktrees of ONE store: `cur` (colocated primary) and `x` (a secondary
# clone of `cur`, both under a project root's `work/`, so `//x` resolves per
# [/wiki/URI] step 2/4).  `x` advances one commit past `cur`.  `head //x` from
# `cur` must resolve `//x`'s OWN rev (its last get/post row — resolve_hash step
# 5.5) via core/resolve_hash.js, then verdict it with the SAME local
# relate.verdict/dag spine `head ?branch` uses — reporting cur BEHIND x's tip
# (a `miss` row + the tip's hashlet) and the changed FILE path — with NO wire
# opened (BE-033/DIS-016: a scheme-less `//X` is never a cached remote).
# SUT=verbs/head/head.js + core/resolve_hash.js; JS-ONLY, no ssh/git/network.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/wire/head-worktree
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "head-worktree: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "head-worktree: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/wire/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink (jab's upward be/-scan).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# URI-016: a PROJECT ROOT at $WORK (rs_work_root seeds its `.be` anchor and echoes
# `work/`) holding TWO worktrees of the SAME store: `cur` (colocated primary) and
# `x` (a SECONDARY clone of `cur`, `//x` == <root>/work/x per [/wiki/URI] step 2).
# The root is DETECTED by the cwd climb (core/resolve_hash.js::projectRoot), never
# named by an env var; $TMP/$$/.be above it is the hermetic firewall (empty file,
# anchors nothing), so BE_ROOT need not be exported here.
_WORKD=$(rs_work_root "$WORK")
CUR="$_WORKD/cur"; X="$_WORKD/x"
mkdir -p "$CUR/.be"
( cd "$CUR" && printf 'A\n' > a.txt && "$JABC" post '#baseA' >/dev/null 2>&1 ) \
    || _fail "cur seed (post baseA) failed"
CURSHA=$(strings "$CUR/.be/wtlog" 2>/dev/null | grep -oE '[0-9a-f]{40}' | tail -1)
[ -n "$CURSHA" ] || _fail "could not read cur's tip sha from its wtlog"

# `x`: a SECONDARY worktree pinned to cur's own tip via a `#sha` pin (not `?/`
# trunk) — sidesteps the store's shared refs ULOG entirely, so this fixture
# does not depend on it.  Then `x` advances ONE commit past `cur`.
mkdir -p "$X"
( cd "$X" && "$JABC" get "file:$CUR/.be#$CURSHA" >/dev/null 2>&1 ) \
    || _fail "x secondary clone (pinned to cur's tip) failed"
[ -f "$X/.be" ] || _fail "x/.be is not a FILE redirect (setup broke)"
( cd "$X" && printf 'B\n' > b.txt && "$JABC" put b.txt >/dev/null 2>&1 \
    && "$JABC" post '#addB' >/dev/null 2>&1 ) || _fail "x advance (post addB) failed"
XSHA=$(strings "$X/.be" 2>/dev/null | grep -oE '[0-9a-f]{40}' | tail -1)
[ -n "$XSHA" ] && [ "$XSHA" != "$CURSHA" ] || _fail "x did not advance past cur"
x8=$(printf '%s' "$XSHA" | cut -c1-8)

KBEFORE=$(find "$_WORKD" -name '*.keeper' | wc -l | tr -d ' ')

# THE ACT: from `cur`, `head //x` — reports cur (still at A) vs x's OWN rev
# (its last get/post row), no wire.
( cd "$CUR" && "$JABC" head '//x' ) >"$WORK/h.out" 2>"$WORK/h.err" \
    || { cat "$WORK/h.err" >&2; _fail "head //x exited non-zero:
$(cat "$WORK/h.out")"; }

dump() { echo "--- out ---"; cat "$WORK/h.out"; }

# (a) cur is BEHIND x's tip: a `miss` row naming x's commit.
grep -qw miss "$WORK/h.out" || { dump; _fail "no behind 'miss' row"; }
grep -q "$x8" "$WORK/h.out" || { dump; _fail "x's tip $x8 not reported"; }
# (b) the changed FILE path (b.txt, added on x) is reported.
grep -qE 'chg[[:space:]]+b\.txt' "$WORK/h.out" || { dump; _fail "b.txt not reported changed"; }
echo "ok: head //x reports cur behind x's rev ($x8), b.txt changed"

# (c) NO WIRE: a scheme-less `//x` must never open the wire (BE-033/DIS-016) —
# the local peek is read-only, so NO new pack lands anywhere under the project.
KAFTER=$(find "$_WORKD" -name '*.keeper' | wc -l | tr -d ' ')
[ "$KAFTER" = "$KBEFORE" ] \
    || _fail "head //x wrote a packlog (.keeper $KBEFORE -> $KAFTER) — opened the wire?"
echo "ok: head //x opened no wire (no new .keeper)"

echo "PASS [$NAME]"
