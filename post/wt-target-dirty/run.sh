#!/bin/sh
# test/post/wt-target-dirty — POST-027 cell 4-dirty: `post //B` where B is
# BEHIND and carries a NON-conflicting local edit in ANOTHER file must 3-WAY
# MERGE, not clobber: B's local edit SURVIVES, A's new content ARRIVES, and
# only then B's base FFs to cur's tip.
# Spec: /wiki/POST.mkd §"Summary of invocation patterns" row 4 — "merge the
# files into the target first ..., then FF the target's base"; advanceWorktree
# (post.js:318-367) reuses the get merge fan-out (getverb.mergeWorktreeTo,
# :345-347) with the target's old base as the 3-way base.
#
# Fixture: A commits c1 {a.txt=A, b.txt=b-orig}; B clones at c1 and DIRTIES
# b.txt (b-LOCAL, unstaged); A commits c2 changing ONLY a.txt (A->A2).
# `(cd A && jab post //B)` must leave B with a.txt=A2 AND b.txt=b-LOCAL,
# base = A's c2 tip.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/wt-target-dirty
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/wt-target-dirty: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/wt-target-dirty: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=wt-target-dirty
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [post/$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [post/$NAME]"; }

. "$_ROOT/lib/repo-setup.sh"

# URI-016: SRC is the PROJECT ROOT; `SRC/work/NAME` IS `//NAME` (rs_work_root,
# the test/post/wt-target pattern).  BE_ROOT confines the climb above SRC.
SRC="$WORK/src"
WORKD=$(rs_work_root "$SRC")
ln -sfn "$BEDIR" "$SRC/jsrc"
export BE_ROOT="$WORK"

_base() {   # _base DIR — the worktree's OWN cur row (wtlog curTip) sha
    cat > "$WORK/.base.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const c=wtlog.open(info).curTip();
const u=utf8.Encode(((c&&c.sha)||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.base.js" "$1" "$BEDIR" 2>/dev/null
}

# --- worktree A: commit c1 {a.txt, b.txt} ------------------------------------
mkdir -p "$WORKD/A/.be"
( cd "$WORKD/A" && printf 'A\n' > a.txt && printf 'b-orig\n' > b.txt \
    && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "A bootstrap post failed"
C1=$(_base "$WORKD/A")

# --- worktree B: clone at c1, then DIRTY b.txt (unstaged local edit) ---------
mkdir -p "$WORKD/B"
( cd "$WORKD/B" && "$BE" get "file://$WORKD/A/.be#$C1" ) >/dev/null 2>&1 \
    || _fail "B clone failed"
[ "$(cat "$WORKD/B/b.txt")" = "b-orig" ] || _fail "fixture: B b.txt != b-orig"
printf 'b-LOCAL\n' > "$WORKD/B/b.txt"

# --- A commits c2: changes ONLY a.txt (no overlap with B's dirty b.txt) ------
( cd "$WORKD/A" && printf 'A2\n' > a.txt && "$JABC" put a.txt && "$JABC" post '#c2' ) >/dev/null 2>&1 \
    || _fail "A c2 post failed"
A_TIP=$(_base "$WORKD/A")
[ "$A_TIP" != "$C1" ] || _fail "fixture: A did not advance past c1"

A_WTLOG_BEFORE=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)

# --- the op under test: `post //B` must 3-way merge the DIRTY target ---------
RC=0
( cd "$WORKD/A" && "$JABC" post '//B' ) >"$WORK/post.out" 2>"$WORK/post.err" || RC=$?
[ "$RC" = 0 ] || { echo "  stderr: $(cat "$WORK/post.err")" >&2; \
                   echo "  stdout: $(cat "$WORK/post.out")" >&2; \
                   _fail "post //B onto a dirty (non-conflicting) target exit $RC"; }

# 1. A's new content ARRIVED.
[ "$(cat "$WORKD/B/a.txt")" = "A2" ] \
    || _fail "A's change did not arrive (B/a.txt='$(cat "$WORKD/B/a.txt")' want 'A2')"
# 2. B's local edit SURVIVED (3-way merge, not a clobbering checkout).
[ "$(cat "$WORKD/B/b.txt")" = "b-LOCAL" ] \
    || _fail "B's local edit was clobbered (B/b.txt='$(cat "$WORKD/B/b.txt")' want 'b-LOCAL')"
# 3. B's base FF-advanced to A's tip.
B_BASE1=$(_base "$WORKD/B")
[ "$B_BASE1" = "$A_TIP" ] \
    || _fail "post //B did not FF B's base (got $B_BASE1 want $A_TIP)"
# 4. A's own wtlog untouched (a one-way advance of B).
A_WTLOG_AFTER=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)
[ "$A_WTLOG_AFTER" = "$A_WTLOG_BEFORE" ] \
    || _fail "post //B mutated A's own wtlog ($A_WTLOG_BEFORE -> $A_WTLOG_AFTER)"

echo "ok   post //B 3-way merged the dirty B (a.txt=A2 arrived, b.txt=b-LOCAL kept)"
pass
