#!/bin/sh
# test/post/conf-state — POST-032: `post //B` onto a target whose pending
# edit CONFLICTS completes per the bare-track ruling (2026-07-18): the weave
# runs, fences stay in B with B's side inside, ONE durable `con` row lands
# in B's wtlog, and B's base ADVANCES (FF) — conflict is a reported STATE,
# never a hard error, never a bare GETCONF code.  Overturns the POST-027
# cell-4 refusal that test/post/wt-target-conflict still encodes.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/conf-state
_WT=$(cd "$_CASE/../../.." && pwd)               # the jsrc root under test
JAB=${JABC:-jab}
command -v "$JAB" >/dev/null 2>&1 || { echo "post/conf-state: SKIP — no jab" >&2; exit 0; }

: "${TMP:=/tmp}"
WORK="$TMP/$$/post-conf-state"
rm -rf "$WORK"; mkdir -p "$WORK"
ln -sfn "$_WT" "$WORK/jsrc"                      # exercise THIS post/get
: > "$TMP/$$/.be" 2>/dev/null || true            # be.find firewall

fail() { echo "FAIL [post/conf-state] $*" >&2; exit 1; }
# _base DIR — the worktree's own cur (wtlog curTip) sha
_base() {
    cat > "$WORK/.base.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const c=wtlog.open(be.treeAt(process.argv[2])).curTip();
const u=utf8.Encode(((c&&c.sha)||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JAB" "$WORK/.base.js" "$1" "$_WT" 2>/dev/null
}
# _conrows DIR — count durable `con` rows in DIR's wtlog
_conrows() {
    cat > "$WORK/.conrows.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const r=wtlog.open(be.treeAt(process.argv[2]));
let n=0;for(const row of r.rows)if(row.verb==="con")n++;
const u=utf8.Encode(n+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JAB" "$WORK/.conrows.js" "$1" "$_WT" 2>/dev/null
}

# --- A: c1 with the future conflict file; a work/ root so //B resolves ---
# URI-016 (the wt-target-conflict pattern): the project root carries `.be` +
# `work/`; `//B` IS `work/B`, the climb bounded by BE_ROOT.
WORKD="$WORK/proj/work"; mkdir -p "$WORK/proj/.be" "$WORKD"
ln -sfn "$_WT" "$WORK/proj/jsrc"
export BE_ROOT="$WORK"
mkdir -p "$WORKD/A/.be"
( cd "$WORKD/A" && printf 'l1\nl2\nl3\nl4\nl5\n' > conf.txt && "$JAB" post 'c1' ) >/dev/null 2>&1 \
    || fail "A bootstrap post"
C1=$(_base "$WORKD/A")
[ -n "$C1" ] || fail "no c1 tip"

# --- B: clone at c1, dirty the last line (MINE) ---
mkdir -p "$WORKD/B"
( cd "$WORKD/B" && "$JAB" get "file://$WORKD/A/.be#$C1" ) >/dev/null 2>&1 || fail "B clone"
printf 'l1\nl2\nl3\nl4\nMINE\n' > "$WORKD/B/conf.txt"

# --- A commits c2 on the SAME line (THEIRS) -> a true 3-way conflict ---
( cd "$WORKD/A" && printf 'l1\nl2\nl3\nl4\nTHEIRS\n' > conf.txt \
    && "$JAB" put conf.txt && "$JAB" post 'c2' ) >/dev/null 2>&1 || fail "A c2 post"
A_TIP=$(_base "$WORKD/A")
[ "$A_TIP" != "$C1" ] || fail "fixture: A did not advance"

# --- the op under test: post //B completes, marks, records, FF-advances ---
rc=0
( cd "$WORKD/A" && "$JAB" post '//B' ) >"$WORK/post.out" 2>"$WORK/post.err" || rc=$?
[ "$rc" = 0 ] || { cat "$WORK/post.err"; fail "conflict must NOT hard-err (exit=$rc)"; }
grep -q 'GETCONF' "$WORK/post.err" && fail "bare GETCONF code leaked to the user"
grep -q 'merged with conflicts' "$WORK/post.err" || \
    { cat "$WORK/post.err"; fail "missing plain-words conflict state line"; }
grep -q '<<<<' "$WORKD/B/conf.txt" || fail "B/conf.txt lacks conflict markers"
grep -q 'MINE' "$WORKD/B/conf.txt" || fail "B's side missing from the conflict"
B_BASE=$(_base "$WORKD/B")
[ "$B_BASE" = "$A_TIP" ] || fail "B's base did not FF-advance (got $B_BASE want $A_TIP)"
[ "$(_conrows "$WORKD/B")" = 1 ] || fail "want ONE con row in B, got $(_conrows "$WORKD/B")"
[ "$(_conrows "$WORKD/A")" = 0 ] || fail "stray con row in A's wtlog"

rm -rf "$TMP/$$"
echo "PASS [post/conf-state]"
