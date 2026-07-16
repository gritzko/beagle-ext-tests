#!/bin/sh
# test/post/bare-advance — DIS-074: a bare `post` on a CLEAN worktree is the
# ADVANCE arm; its target defaults to the URI the worktree TRACKS (the
# recentmost `get` record).  worktree.mkd:50-54 is the authority: `post "msg"`
# commits (the tree goes ahead), then a second BARE `post` fast-forwards the
# tracked thing.  Both track shapes are covered:
#   * a `?feat` BRANCH track   -> the branch ref FFs to cur's tip (advanceBranch)
#   * a `//X` WORKTREE track   -> X's own base FFs to cur's tip (advanceWorktree)
# RED today: both throw `POSTNONE: no changes since base` (post.js's empty-
# commit refuse) — after the DIS-076 commit/advance split there is NO reachable
# bare advance at all.  Also asserts the already-up-to-date bare post reports a
# CLEAR "already at" POSTNONE, not the commit-shaped "no changes since base".
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/bare-advance
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/bare-advance: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/bare-advance: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=bare-advance
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [post/$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [post/$NAME]"; }

. "$_ROOT/lib/repo-setup.sh"

# URI-016: SRC is the PROJECT ROOT (its own `.be/` anchor); `SRC/work/NAME` IS
# `//NAME` (rs_work_root, the test/post/wt-target pattern).  BE_ROOT confines
# the climb above SRC.
SRC="$WORK/src"
WORKD=$(rs_work_root "$SRC")
ln -sfn "$BEDIR" "$SRC/jsrc"
export BE_ROOT="$WORK"

# tip capture: the worktree's own cur via `jab refs` — never od/grep `.be/refs`.
_cur() { ( cd "$1" && "$JABC" refs ) 2>/dev/null | sed -n 's/^cur: *//p'; }

# a branch's REFS tip in DIR's store (assertion probe; resolution stays in
# shared/store.js resolveRef — not a re-implementation).
_ref() {   # _ref DIR BRANCH
    cat > "$WORK/.ref.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const info=be.treeAt(process.argv[2]);
const k=store.open(info.storePath,info.project);
const t=k.resolveRef(process.argv[4]||"")||"";
const u=utf8.Encode(t+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.ref.js" "$1" "$BEDIR" "$2" 2>/dev/null
}

# ===== shape 1: a `?feat` BRANCH track =======================================
# A bootstraps its own store, publishes `?feat` at c1, SWITCHES to track feat
# (`get ?feat` — the recentmost get record now says feat), then commits c2.
# The wt is clean and AHEAD of feat; a bare `post` must FF feat to c2.
A="$WORKD/A"; mkdir -p "$A/.be"
( cd "$A" && printf 'one\n' > f.txt && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "A: bootstrap post c1 failed"
( cd "$A" && "$JABC" post '?feat' ) >/dev/null 2>&1 \
    || _fail "A: publish ?feat failed"
( cd "$A" && "$JABC" get '?feat' ) >/dev/null 2>&1 \
    || _fail "A: switch to ?feat failed"
( cd "$A" && printf 'two\n' > f.txt && "$JABC" put f.txt && "$JABC" post '#c2' ) >/dev/null 2>&1 \
    || _fail "A: post c2 failed"
A_TIP=$(_cur "$A")
[ -n "$A_TIP" ] || _fail "A: no cur tip"
FEAT0=$(_ref "$A" feat)
[ -n "$FEAT0" ] && [ "$FEAT0" != "$A_TIP" ] \
    || _fail "fixture: feat not behind cur (feat=$FEAT0 cur=$A_TIP)"

RC=0
( cd "$A" && "$JABC" post ) >"$WORK/a.out" 2>"$WORK/a.err" || RC=$?
FEAT1=$(_ref "$A" feat)
if [ "$RC" -ne 0 ] || [ "$FEAT1" != "$A_TIP" ]; then
    echo "post/bare-advance: RED (rc=$RC) — bare post did not FF the ?feat track" >&2
    echo "  stdout: $(cat "$WORK/a.out")" >&2
    echo "  stderr: $(cat "$WORK/a.err")" >&2
    echo "  feat before=$FEAT0 after=$FEAT1 want=$A_TIP" >&2
    _fail "bare post did not FF the tracked branch (see above)"
fi
[ "$(_cur "$A")" = "$A_TIP" ] || _fail "bare post moved A's own cur (must stay $A_TIP)"

# already up to date: a SECOND bare post refuses with a CLEAR "already at
# cur's tip" — never the commit-shaped "no changes since base".
RC=0
( cd "$A" && "$JABC" post ) >"$WORK/a2.out" 2>"$WORK/a2.err" || RC=$?
[ "$RC" -ne 0 ] || _fail "up-to-date bare post did not refuse: $(cat "$WORK/a2.out")"
grep -q "already at cur's tip" "$WORK/a2.err" \
    || _fail "up-to-date bare post refused but not 'already at cur's tip': $(cat "$WORK/a2.err")"
if grep -q "no changes since base" "$WORK/a2.err"; then
    _fail "up-to-date bare post still reports 'no changes since base': $(cat "$WORK/a2.err")"
fi

# ===== shape 2: a `//X` WORKTREE track =======================================
# A REAL layout (the test/get/wt-operand pattern): ONE shared store at the
# project root, worktrees CLONE it (never bootstrap their own — resolve_hash
# step 1 reads the PROJECT store).  S is the upstream tree; D clones it via
# the DIS-063 `get //S` operand (the track record is `//S#<sha>`), commits s2,
# then a bare `post` in D must FF S's own base to D's tip (worktree.mkd:50-54).
( cd "$SRC" && printf 'readme\n' > readme.txt && "$BE" post '#main' ) >/dev/null 2>&1 \
    || _fail "main tree: bootstrap post failed"
MAIN_SHA=$(_cur "$SRC")
[ -n "$MAIN_SHA" ] || _fail "main tree: no cur tip"
S="$WORKD/S"; mkdir -p "$S"
( cd "$S" && "$JABC" get "file:$SRC/.be#$MAIN_SHA" ) >/dev/null 2>&1 \
    || _fail "S: clone of the shared store failed"
( cd "$S" && printf 'src\n' > s.txt && "$JABC" put s.txt && "$JABC" post '#s1' ) >/dev/null 2>&1 \
    || _fail "S: post s1 failed"
D="$WORKD/D"; mkdir -p "$D"
( cd "$D" && "$JABC" get '//S' ) >/dev/null 2>&1 \
    || _fail "D: clone //S failed"
[ "$(_cur "$D")" = "$(_cur "$S")" ] || _fail "fixture: D's base is not S's tip"
( cd "$D" && printf 'src2\n' > s.txt && "$JABC" put s.txt && "$JABC" post '#s2' ) >/dev/null 2>&1 \
    || _fail "D: post s2 failed"
D_TIP=$(_cur "$D")
S0=$(_cur "$S")
[ -n "$D_TIP" ] && [ "$S0" != "$D_TIP" ] \
    || _fail "fixture: S not behind D (S=$S0 D=$D_TIP)"
D_WTLOG_BEFORE=$(wc -c < "$D/.be" 2>/dev/null || echo 0)

RC=0
( cd "$D" && "$JABC" post ) >"$WORK/d.out" 2>"$WORK/d.err" || RC=$?
S1=$(_cur "$S")
if [ "$RC" -ne 0 ] || [ "$S1" != "$D_TIP" ]; then
    echo "post/bare-advance: RED (rc=$RC) — bare post did not FF the //S track" >&2
    echo "  stdout: $(cat "$WORK/d.out")" >&2
    echo "  stderr: $(cat "$WORK/d.err")" >&2
    echo "  S base before=$S0 after=$S1 want=$D_TIP" >&2
    _fail "bare post did not FF the tracked worktree (see above)"
fi
[ "$(_cur "$D")" = "$D_TIP" ] || _fail "bare post moved D's own cur (must stay $D_TIP)"
D_WTLOG_AFTER=$(wc -c < "$D/.be" 2>/dev/null || echo 0)
[ "$D_WTLOG_AFTER" = "$D_WTLOG_BEFORE" ] \
    || _fail "bare post mutated D's own wtlog ($D_WTLOG_BEFORE -> $D_WTLOG_AFTER bytes)"

pass
