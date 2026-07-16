#!/bin/sh
# test/post/wt-target-nonff — POST-027 cell 1b/4-v: `post //B` where A and B
# DIVERGED (both committed past a common base) must refuse POSTNOFF
# (advanceWorktree post.js:318-367, the relate.verdict non-`behind` arm at
# :335-338) — B's base does NOT move and B's files stay untouched.
# Spec: /wiki/POST.mkd §"Summary of invocation patterns" row 4 — every tip
# motion is a FAST-FORWARD; a diverged target cannot FF.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/wt-target-nonff
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/wt-target-nonff: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/wt-target-nonff: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=wt-target-nonff
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

# --- worktree A: bootstrap a fresh store, commit the common base c1 ---------
mkdir -p "$WORKD/A/.be"
( cd "$WORKD/A" && printf 'A\n' > a.txt && printf 'B\n' > b.txt && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "A bootstrap post failed"
C1=$(_base "$WORKD/A")

# --- worktree B: clone at c1 (shares A's store) ------------------------------
mkdir -p "$WORKD/B"
( cd "$WORKD/B" && "$BE" get "file://$WORKD/A/.be#$C1" ) >/dev/null 2>&1 \
    || _fail "B clone failed"

# --- DIVERGE: both commit past c1 --------------------------------------------
( cd "$WORKD/A" && printf 'A2\n' > a.txt && "$JABC" put a.txt && "$JABC" post '#a2' ) >/dev/null 2>&1 \
    || _fail "A a2 post failed"
( cd "$WORKD/B" && printf 'B2\n' > b.txt && "$JABC" put b.txt && "$JABC" post '#b2' ) >/dev/null 2>&1 \
    || _fail "B b2 post failed"
A_TIP=$(_base "$WORKD/A")
B_BASE0=$(_base "$WORKD/B")
[ "$A_TIP" != "$C1" ] && [ "$B_BASE0" != "$C1" ] && [ "$A_TIP" != "$B_BASE0" ] \
    || _fail "fixture: A and B did not diverge (A=$A_TIP B=$B_BASE0 c1=$C1)"

A_WTLOG_BEFORE=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)

# --- the op under test: `post //B` on a diverged target ----------------------
RC=0
( cd "$WORKD/A" && "$JABC" post '//B' ) >"$WORK/post.out" 2>"$WORK/post.err" || RC=$?

[ "$RC" -ne 0 ] || { echo "  stdout: $(cat "$WORK/post.out")" >&2; \
    _fail "post //B SUCCEEDED — a diverged target must refuse POSTNOFF"; }
grep -q 'can not be fast-forwarded' "$WORK/post.err" \
    || { cat "$WORK/post.err" >&2; _fail "refusal is not the non-FF report"; }

# B untouched: base still at its own b2, files keep B's content.
[ "$(_base "$WORKD/B")" = "$B_BASE0" ] || _fail "post //B moved B's base (non-FF!)"
[ "$(cat "$WORKD/B/b.txt")" = "B2" ] \
    || _fail "post //B touched B's b.txt (got '$(cat "$WORKD/B/b.txt")' want 'B2')"
[ "$(cat "$WORKD/B/a.txt")" = "A" ] \
    || _fail "post //B touched B's a.txt (got '$(cat "$WORKD/B/a.txt")' want 'A')"
A_WTLOG_AFTER=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)
[ "$A_WTLOG_AFTER" = "$A_WTLOG_BEFORE" ] \
    || _fail "post //B mutated A's own wtlog ($A_WTLOG_BEFORE -> $A_WTLOG_AFTER)"

pass
