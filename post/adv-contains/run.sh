#!/bin/sh
# test/post/adv-contains — POST-027 cells 1a-iii + 3-iii: the target branch
# CONTAINS cur (cur's tip is an ANCESTOR of the branch tip — the target is
# already PAST cur).  POST.mkd §"Summary of invocation patterns" cell 1a:
# "FF its ref to cur's tip; POSTNONE if already at/past it, POSTNOFF if
# non-FF" — a target that already contains cur is the "already PAST"
# POSTNONE (post.js:291's contains arm), NEVER a POSTNOFF.  Both entries are
# covered: the explicit `post '?feat'` (cell 3-iii) and a bare `post` on a
# `?feat` track (cell 1a-iii).  Either refusal leaves the wt byte-intact.
# Fixture: A commits c1 then c2, publishes `?feat` at c2, then re-attaches
# to feat PINNED at c1 (`get '?feat#<c1>'`) — track=feat, cur=c1, feat=c2.
# RED today: advanceBranch's FF gate (post.js:287, POSTNOFF "not an ancestor
# of cur") fires BEFORE the contains arm (post.js:291), so a containing
# target refuses POSTNOFF and the POSTNONE "already contains" arm is
# unreachable dead code — both legs get the wrong refusal class.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/adv-contains
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/adv-contains: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/adv-contains: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=adv-contains
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

# The rolling keeper.idx indexes only the LATEST keeper (the test/post/
# patch-absorb note); drop the stale idx before ops that read older commits.
_fresh() { rm -f "$1"/.be/*.keeper.idx "$1"/.be/*/*.keeper.idx 2>/dev/null || true; }

# ===== fixture: feat CONTAINS cur ============================================
A="$WORKD/A"; mkdir -p "$A/.be"
( cd "$A" && printf 'one\n' > f.txt && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "A: bootstrap post c1 failed"
C1=$(_cur "$A"); [ -n "$C1" ] || _fail "A: no c1 tip"
( cd "$A" && printf 'two\n' > f.txt && "$JABC" put f.txt && "$JABC" post '#c2' ) >/dev/null 2>&1 \
    || _fail "A: post c2 failed"
C2=$(_cur "$A"); [ -n "$C2" ] && [ "$C2" != "$C1" ] || _fail "A: no distinct c2 tip"
( cd "$A" && "$JABC" post '?feat' ) >/dev/null 2>&1 \
    || _fail "A: publish ?feat at c2 failed"
_fresh "$A"
( cd "$A" && "$JABC" get "?feat#$C1" ) >/dev/null 2>&1 \
    || _fail "A: re-attach ?feat pinned at c1 failed"
[ "$(_cur "$A")" = "$C1" ] || _fail "fixture: cur != c1 after the pinned get"
[ "$(_ref "$A" feat)" = "$C2" ] || _fail "fixture: feat != c2 (feat=$(_ref "$A" feat))"
[ "$(cat "$A/f.txt")" = "one" ] || _fail "fixture: f.txt not at c1's bytes"

# ===== leg 1 (3-iii): explicit `post '?feat'` on a containing target ========
_fresh "$A"
RC=0
( cd "$A" && "$JABC" post '?feat' ) >"$WORK/e.out" 2>"$WORK/e.err" || RC=$?
[ "$RC" -ne 0 ] \
    || _fail "explicit ?feat on a containing target did not refuse: $(cat "$WORK/e.out")"
[ "$(_ref "$A" feat)" = "$C2" ] || _fail "explicit refusal moved feat"
[ "$(_cur "$A")" = "$C1" ]      || _fail "explicit refusal moved cur"
[ "$(cat "$A/f.txt")" = "one" ] || _fail "explicit refusal touched the wt bytes"
if ! grep -q "already contains cur's tip" "$WORK/e.err"; then
    echo 'post/adv-contains: RED — a containing `?feat` must refuse "already contains" (POST.mkd cell 3: target already past cur), got:' >&2
    echo "  stderr: $(cat "$WORK/e.err")" >&2
    _fail 'explicit `post ?feat` refused with the wrong class (want POSTNONE "already contains")'
fi

# ===== leg 2 (1a-iii): bare `post` on the containing feat track =============
_fresh "$A"
RC=0
( cd "$A" && "$JABC" post ) >"$WORK/b.out" 2>"$WORK/b.err" || RC=$?
[ "$RC" -ne 0 ] \
    || _fail "bare post on a containing feat track did not refuse: $(cat "$WORK/b.out")"
[ "$(_ref "$A" feat)" = "$C2" ] || _fail "bare refusal moved feat"
[ "$(_cur "$A")" = "$C1" ]      || _fail "bare refusal moved cur"
[ "$(cat "$A/f.txt")" = "one" ] || _fail "bare refusal touched the wt bytes"
if ! grep -q "already contains cur's tip" "$WORK/b.err"; then
    echo 'post/adv-contains: RED — a bare post on a feat track that contains cur must refuse "already contains" (POST.mkd cell 1a: already at/past it), got:' >&2
    echo "  stderr: $(cat "$WORK/b.err")" >&2
    _fail 'bare post on a containing track refused with the wrong class (want POSTNONE "already contains")'
fi

pass
