#!/bin/sh
# test/post/wt-target — DIS-062: `post //X[/sub]` FF-advances another LOCAL
# worktree from cur's tip (worktree.mkd: "all worktrees may get/post from/to
# each other directly").  This needs a `//NAME` nav address, which resolves
# only under `<project root>/work/` ([/wiki/URI] step 2) — unlike the plain
# postcase.sh scratch, so this case builds its own SRC/work fixture (the
# rs_work_root pattern test/bro/ticket/run.sh uses), not postcase.sh.
#
# Fixture: two worktrees A, B under $SRC/work; B is a secondary wt cloned off
# A's store (so both share ONE store — the local FF-check reads one reader,
# same as head.js's own DIS-062 peek).  A commits past B's base (FF-able
# divergence), then `(cd A && jab post //B)` must FF-advance B's base to A's
# tip while leaving A's own wtlog untouched.
#
# DIS-062/DIS-076 coordination: the `//B` operand only survives intact once
# core/loop.js's authorityRepo classifier (a separate, in-flight fix) lets an
# explicit operand (cwd NOT inside B) through instead of eating it as nav
# context.  If that has not landed, this case is expected RED — it pins the
# defect, not a fake pass.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/wt-target
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/wt-target: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/wt-target: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=wt-target
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [post/$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [post/$NAME]"; }

. "$_ROOT/lib/repo-setup.sh"

# URI-016: SRC is the PROJECT ROOT (its own `.be/` anchor); `SRC/work/NAME` IS
# `//NAME`.  BE_ROOT confines the climb above SRC (test/bro/ticket's pattern).
SRC="$WORK/src"
WORKD=$(rs_work_root "$SRC")
ln -sfn "$BEDIR" "$SRC/jsrc"
export BE_ROOT="$WORK"

# DIS-076: a commit no longer touches any REF (WT-only motion, this tree's own
# uncommitted change — preserved, not reverted here), so there is no trunk ref
# to read; `_base` (the wtlog cur row) is the ONLY tip a worktree has.
# base helper: the worktree's OWN cur row (wtlog.js curTip) — what `post //B`
# must FF-advance; this is what resolve_hash step 5.5 reads too.
_base() {   # _base DIR
    cat > "$WORK/.base.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const c=wtlog.open(info).curTip();
const u=utf8.Encode(((c&&c.sha)||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.base.js" "$1" "$BEDIR" 2>/dev/null
}

# --- worktree A: bootstrap a fresh store, commit c1 -------------------------
mkdir -p "$WORKD/A/.be"
( cd "$WORKD/A" && printf 'A\n' > a.txt && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "A bootstrap post failed"
A_TIP0=$(_base "$WORKD/A")

# --- worktree B: clone A's store at A's c1 tip (secondary wt, SHARES A's
# store) — DIS-076 dropped the ref write on commit, so a bare `file://` clone
# (which reads the trunk REF) has nothing to resolve; pin the fragment to
# A's own wtlog tip instead (D1/D2, no ref involved).
mkdir -p "$WORKD/B"
( cd "$WORKD/B" && "$BE" get "file://$WORKD/A/.be#$A_TIP0" ) >/dev/null 2>&1 \
    || _fail "B clone failed"

B_BASE0=$(_base "$WORKD/B")
[ "$B_BASE0" = "$A_TIP0" ] || _fail "fixture: B's base is not A's c1 tip (got $B_BASE0, want $A_TIP0)"

# --- A advances past B's base: c2 (an FF-able divergence) -------------------
( cd "$WORKD/A" && printf 'A2\n' > a.txt && "$BE" put a.txt && "$BE" post '#c2' ) >/dev/null 2>&1 \
    || _fail "A c2 post failed"
A_TIP=$(_base "$WORKD/A")
[ "$A_TIP" != "$B_BASE0" ] || _fail "fixture: A did not advance past B's base"

A_WTLOG_BEFORE=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)

# --- the op under test: from A, `post //B` FF-advances B's base to A's tip --
RC=0
( cd "$WORKD/A" && "$JABC" post "//B" ) >"$WORK/postB.out" 2>"$WORK/postB.err" || RC=$?

B_BASE1=$(_base "$WORKD/B")
A_WTLOG_AFTER=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)

if [ "$RC" -ne 0 ] || [ "$B_BASE1" != "$A_TIP" ]; then
    echo "post/wt-target: RED (rc=$RC) — 'post //B' did not FF-advance B" >&2
    echo "  stdout: $(cat "$WORK/postB.out")" >&2
    echo "  stderr: $(cat "$WORK/postB.err")" >&2
    echo "  B base before=$B_BASE0 after=$B_BASE1 want=$A_TIP" >&2
    echo "post/wt-target: EXPECTED red if core/loop.js's authorityRepo" >&2
    echo "  classifier (DIS-062, coordinated in-flight fix) does not yet let an" >&2
    echo "  explicit //B operand reach post.js intact — see DIS-062." >&2
    _fail "post //B did not FF-advance B (see above)"
fi

[ "$A_WTLOG_AFTER" = "$A_WTLOG_BEFORE" ] \
    || _fail "post //B mutated A's own wtlog (must leave A untouched: $A_WTLOG_BEFORE -> $A_WTLOG_AFTER)"

pass
