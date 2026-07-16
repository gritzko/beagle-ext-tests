#!/bin/sh
# test/post/wt-target-merge — POST-026 repro (b): a `//WT` target post must
# MATERIALISE the dirties into the target worktree (a get-style checkout/merge),
# not merely move the target's base hash.
#
# The old advanceWorktree ONLY appended a base-advance row to the target's
# wtlog — the target's FILES were left STALE (only the recorded base moved).
# POST-026 spec: FF-advance a `//WT` target by REUSING the get merge path — check
# out / 3-way merge the dirties into the target wt FIRST, THEN advance its base
# (branch retained).  A DIRTY target is merged like get; a conflict refuses.
#
# Fixture (as test/post/wt-target): two worktrees A, B under $SRC/work sharing
# ONE store; B is cloned at A's c1 tip.  A commits c2 (edits a.txt A->A2, adds
# c.txt).  `(cd A && jab post //B)` must FF-advance B AND update B's files:
#   * B/a.txt becomes A2   (an existing tracked file was refreshed)
#   * B/c.txt appears       (a new tracked file was checked out)
# A clean B (no local edits) is a clean overwrite; A's own wtlog stays untouched.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)
_ROOT=$(cd "$_CASE/../.." && pwd)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/wt-target-merge: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/wt-target-merge: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=wt-target-merge
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [post/$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [post/$NAME]"; }

. "$_ROOT/lib/repo-setup.sh"

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

# --- worktree A: bootstrap a fresh store, commit c1 -------------------------
mkdir -p "$WORKD/A/.be"
( cd "$WORKD/A" && printf 'A\n' > a.txt && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "A bootstrap post failed"
A_TIP0=$(_base "$WORKD/A")

# --- worktree B: clone A's store at A's c1 tip (secondary wt, SHARES A's store)
mkdir -p "$WORKD/B"
( cd "$WORKD/B" && "$BE" get "file://$WORKD/A/.be#$A_TIP0" ) >/dev/null 2>&1 \
    || _fail "B clone failed"
B_BASE0=$(_base "$WORKD/B")
[ "$B_BASE0" = "$A_TIP0" ] || _fail "fixture: B base != A c1 tip"
# B starts with a.txt=A (the clone), no c.txt.
[ "$(cat "$WORKD/B/a.txt")" = "A" ] || _fail "fixture: B a.txt != A"
[ ! -e "$WORKD/B/c.txt" ] || _fail "fixture: B already has c.txt"

# --- A advances past B's base: c2 (edit a.txt A->A2, add c.txt) -------------
( cd "$WORKD/A" && printf 'A2\n' > a.txt && printf 'C\n' > c.txt \
    && "$BE" put a.txt c.txt && "$BE" post '#c2' ) >/dev/null 2>&1 \
    || _fail "A c2 post failed"
A_TIP=$(_base "$WORKD/A")
[ "$A_TIP" != "$B_BASE0" ] || _fail "fixture: A did not advance past B's base"

A_WTLOG_BEFORE=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)

# --- the op under test: from A, `post //B` FF-advances B AND materialises it -
RC=0
( cd "$WORKD/A" && "$JABC" post "//B" ) >"$WORK/postB.out" 2>"$WORK/postB.err" || RC=$?
[ "$RC" = 0 ] || { echo "  stderr: $(cat "$WORK/postB.err")"; \
                   echo "  stdout: $(cat "$WORK/postB.out")"; _fail "post //B exit $RC"; }

# 1. B's base FF-advanced to A's tip.
B_BASE1=$(_base "$WORKD/B")
[ "$B_BASE1" = "$A_TIP" ] || _fail "post //B did not FF-advance B base (got $B_BASE1 want $A_TIP)"

# 2. THE FIX (POST-026): B's FILES were materialised, not left stale.
[ "$(cat "$WORKD/B/a.txt")" = "A2" ] \
    || _fail "post //B left B/a.txt STALE (got '$(cat "$WORKD/B/a.txt")' want 'A2')"
[ -f "$WORKD/B/c.txt" ] && [ "$(cat "$WORKD/B/c.txt")" = "C" ] \
    || _fail "post //B did not check out the new B/c.txt"

# 3. A's own wtlog untouched (post //B is a one-way advance of B).
A_WTLOG_AFTER=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)
[ "$A_WTLOG_AFTER" = "$A_WTLOG_BEFORE" ] \
    || _fail "post //B mutated A's own wtlog ($A_WTLOG_BEFORE -> $A_WTLOG_AFTER)"

echo "ok   post //B FF-advanced B and materialised its files (a.txt=A2, c.txt=C)"
pass
