#!/bin/sh
# test/post/wt-target-ahead — POST-027 cell 1b/4-iii: `post //B` where B is
# AHEAD (B's base CONTAINS cur's tip — B committed past the shared base) must
# refuse POSTNONE "already contains" (advanceWorktree post.js:318-367, the
# relate.verdict `ahead` arm at :333-334) and leave B untouched.
# Spec: /wiki/POST.mkd §"Summary of invocation patterns" row 4 — every tip
# motion is a fast-forward; a target that already contains cur has nothing
# to receive.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/wt-target-ahead
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/wt-target-ahead: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/wt-target-ahead: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=wt-target-ahead
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

# --- worktree A: bootstrap a fresh store, commit c1 -------------------------
mkdir -p "$WORKD/A/.be"
( cd "$WORKD/A" && printf 'A\n' > a.txt && printf 'B\n' > b.txt && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "A bootstrap post failed"
A_TIP=$(_base "$WORKD/A")

# --- worktree B: clone A's store at c1, then B COMMITS c2 -> B is AHEAD -----
# (B is a secondary wt SHARING A's store, so A's reader sees B's c2 and the
# ancestry verdict is computable — the wt-target fixture pattern.)
mkdir -p "$WORKD/B"
( cd "$WORKD/B" && "$BE" get "file://$WORKD/A/.be#$A_TIP" ) >/dev/null 2>&1 \
    || _fail "B clone failed"
( cd "$WORKD/B" && printf 'B2\n' > b.txt && "$JABC" put b.txt && "$JABC" post '#c2' ) >/dev/null 2>&1 \
    || _fail "B c2 post failed"
B_BASE0=$(_base "$WORKD/B")
[ -n "$B_BASE0" ] && [ "$B_BASE0" != "$A_TIP" ] \
    || _fail "fixture: B did not advance past A's tip"

A_WTLOG_BEFORE=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)

# --- the op under test: `post //B` with B ahead of cur ----------------------
RC=0
( cd "$WORKD/A" && "$JABC" post '//B' ) >"$WORK/post.out" 2>"$WORK/post.err" || RC=$?

[ "$RC" -ne 0 ] || { echo "  stdout: $(cat "$WORK/post.out")" >&2; \
    _fail "post //B SUCCEEDED — an ahead target must refuse POSTNONE"; }
grep -q "already contains cur's tip" "$WORK/post.err" \
    || { cat "$WORK/post.err" >&2; _fail "refusal does not say 'already contains'"; }

# B untouched: base still at its own c2, files keep B's committed content.
[ "$(_base "$WORKD/B")" = "$B_BASE0" ] || _fail "post //B moved B's base off its own c2"
[ "$(cat "$WORKD/B/b.txt")" = "B2" ] \
    || _fail "post //B touched B's files (b.txt='$(cat "$WORKD/B/b.txt")' want 'B2')"
A_WTLOG_AFTER=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)
[ "$A_WTLOG_AFTER" = "$A_WTLOG_BEFORE" ] \
    || _fail "post //B mutated A's own wtlog ($A_WTLOG_BEFORE -> $A_WTLOG_AFTER)"

pass
