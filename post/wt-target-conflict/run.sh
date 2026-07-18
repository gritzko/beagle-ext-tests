#!/bin/sh
# test/post/wt-target-conflict — `post //B` where B is BEHIND and B's local
# edit CONFLICTS with A's change to the SAME lines.  POST-032 ruling
# (2026-07-18, overturns the POST-027 cell-4 refusal): the weave completes,
# marks the conflict, records ONE durable `con` row in B's wtlog, reports
# "merged with conflicts" in plain words, and B's base FF-ADVANCES.
#
# Like get's own conflict (test/get/confdrop), the weave leaves MARKERS in the
# conflicted file with B's side INSIDE them — B's local edit is never lost,
# never silently overwritten by A's version, and a hand-resolve converges.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/wt-target-conflict
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/wt-target-conflict: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/wt-target-conflict: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=wt-target-conflict
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

# POST-032: count durable `con` rows in DIR's wtlog (the mark+record state).
_conrows() {
    cat > "$WORK/.conrows.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const r=wtlog.open(be.treeAt(process.argv[2]));
let n=0;for(const row of r.rows)if(row.verb==="con")n++;
const u=utf8.Encode(n+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.conrows.js" "$1" "$BEDIR" 2>/dev/null
}

# --- worktree A: commit c1 with the future conflict file ---------------------
mkdir -p "$WORKD/A/.be"
( cd "$WORKD/A" && printf 'l1\nl2\nl3\nl4\nl5\n' > conf.txt && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "A bootstrap post failed"
C1=$(_base "$WORKD/A")

# --- worktree B: clone at c1, then dirty conf.txt's LAST LINE (MINE) ---------
mkdir -p "$WORKD/B"
( cd "$WORKD/B" && "$BE" get "file://$WORKD/A/.be#$C1" ) >/dev/null 2>&1 \
    || _fail "B clone failed"
printf 'l1\nl2\nl3\nl4\nMINE\n' > "$WORKD/B/conf.txt"

# --- A commits c2 changing the SAME line (THEIRS) -> a true 3-way conflict ---
( cd "$WORKD/A" && printf 'l1\nl2\nl3\nl4\nTHEIRS\n' > conf.txt \
    && "$JABC" put conf.txt && "$JABC" post '#c2' ) >/dev/null 2>&1 \
    || _fail "A c2 post failed"
A_TIP=$(_base "$WORKD/A")
[ "$A_TIP" != "$C1" ] || _fail "fixture: A did not advance past c1"

A_WTLOG_BEFORE=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)

# --- the op under test: `post //B` marks, records, FF-advances (POST-032) ----
RC=0
( cd "$WORKD/A" && "$JABC" post '//B' ) >"$WORK/post.out" 2>"$WORK/post.err" || RC=$?

[ "$RC" -eq 0 ] || { cat "$WORK/post.err" >&2; \
    _fail "POST-032: a marked conflict must not hard-err (exit=$RC)"; }
grep -q 'merged with conflicts' "$WORK/post.err" \
    || { cat "$WORK/post.err" >&2; \
         _fail "POST-032: missing plain-words conflict state line"; }

# THE cell assert (POST-032): the base FF-advances past the marked conflict.
B_BASE1=$(_base "$WORKD/B")
[ "$B_BASE1" = "$A_TIP" ] \
    || _fail "POST-032: B's base must FF-advance (got $B_BASE1 want $A_TIP)"
[ "$(_conrows "$WORKD/B")" = 1 ] \
    || _fail "POST-032: want ONE con row in B, got $(_conrows "$WORKD/B")"
# B's side of the edit is intact — present in the file (inside markers, the
# get/confdrop weave shape), never silently replaced by A's version.
grep -q 'MINE' "$WORKD/B/conf.txt" \
    || { echo "--- B/conf.txt ---" >&2; cat "$WORKD/B/conf.txt" >&2; \
         _fail "B's local edit LOST from conf.txt"; }
[ "$(cat "$WORKD/B/conf.txt")" != "$(printf 'l1\nl2\nl3\nl4\nTHEIRS\n')" ] \
    || _fail "B's conf.txt silently clobbered with A's version"
A_WTLOG_AFTER=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)
[ "$A_WTLOG_AFTER" = "$A_WTLOG_BEFORE" ] \
    || _fail "post //B mutated A's own wtlog ($A_WTLOG_BEFORE -> $A_WTLOG_AFTER)"

echo "ok   post //B merged with a marked conflict and B's base FF-advanced"
pass
