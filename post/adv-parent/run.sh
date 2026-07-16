#!/bin/sh
# test/post/adv-parent — POST-027 cell 3 `?..`: the PARENT-branch advance.
# POST.mkd §"Summary of invocation patterns" cell 3: "`?..` parent" — on a
# CHILD branch (`feat/sub`, the plain nested key shape shared/branch.js
# key()s) `post '?..'` FF-moves the PARENT branch (`feat`) to cur's tip; no
# commit, cur untouched, the child ref untouched.  On TRUNK there is no
# parent to climb from, so `post '?..'` refuses POSTQRY (resolveTarget,
# post.js:256) and nothing moves.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/adv-parent
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/adv-parent: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/adv-parent: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=adv-parent
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [post/$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [post/$NAME]"; }

. "$_ROOT/lib/repo-setup.sh"

# URI-016: SRC is the PROJECT ROOT (its own `.be/` anchor); BE_ROOT confines
# the climb above SRC (the test/post/bare-advance pattern).
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

# ===== fixture ===============================================================
A="$WORKD/A"; mkdir -p "$A/.be"
( cd "$A" && printf 'one\n' > f.txt && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "A: bootstrap post c1 failed"
C1=$(_cur "$A"); [ -n "$C1" ] || _fail "A: no c1 tip"

# ===== leg 1: `post '?..'` on TRUNK refuses (no child to climb from) ========
RC=0
( cd "$A" && "$JABC" post '?..' ) >"$WORK/t.out" 2>"$WORK/t.err" || RC=$?
[ "$RC" -ne 0 ] \
    || _fail "post ?.. on trunk did not refuse: $(cat "$WORK/t.out")"
grep -q "needs a child branch" "$WORK/t.err" \
    || _fail "post ?.. on trunk refused but not 'needs a child branch': $(cat "$WORK/t.err")"
[ "$(_cur "$A")" = "$C1" ] || _fail "trunk ?.. refusal moved cur"
[ -z "$(_ref "$A" "")" ]   || _fail "trunk ?.. refusal minted a trunk ref"

# ===== leg 2: `post '?..'` on a child branch FFs the PARENT ==================
# Publish `?feat` and the nested child `?feat/sub` at c1, attach to the child,
# commit c2 — cur is ahead of BOTH; `?..` must move ONLY the parent (feat).
( cd "$A" && "$JABC" post '?feat' ) >/dev/null 2>&1 \
    || _fail "A: publish ?feat failed"
( cd "$A" && "$JABC" post '?feat/sub' ) >/dev/null 2>&1 \
    || _fail "A: publish nested ?feat/sub failed"
( cd "$A" && "$JABC" get '?feat/sub' ) >/dev/null 2>&1 \
    || _fail "A: attach to ?feat/sub failed"
( cd "$A" && printf 'two\n' > f.txt && "$JABC" put f.txt && "$JABC" post '#c2' ) >/dev/null 2>&1 \
    || _fail "A: post c2 failed"
C2=$(_cur "$A"); [ -n "$C2" ] && [ "$C2" != "$C1" ] || _fail "A: no distinct c2 tip"
[ "$(_ref "$A" feat)" = "$C1" ]       || _fail "fixture: feat not at c1"
[ "$(_ref "$A" feat/sub)" = "$C1" ]   || _fail "fixture: feat/sub not at c1"

_fresh "$A"
RC=0
( cd "$A" && "$JABC" post '?..' ) >"$WORK/p.out" 2>"$WORK/p.err" || RC=$?
if [ "$RC" -ne 0 ] || [ "$(_ref "$A" feat)" != "$C2" ]; then
    echo "post/adv-parent: RED (rc=$RC) — ?.. did not FF the parent branch" >&2
    echo "  stdout: $(cat "$WORK/p.out")" >&2
    echo "  stderr: $(cat "$WORK/p.err")" >&2
    echo "  feat=$(_ref "$A" feat) want=$C2" >&2
    _fail "post ?.. on feat/sub did not FF feat (see above)"
fi
# only the parent moved: the child ref, cur and the wt stay put; no commit.
[ "$(_ref "$A" feat/sub)" = "$C1" ] || _fail "?.. moved the CHILD ref feat/sub"
[ "$(_cur "$A")" = "$C2" ]          || _fail "?.. moved cur (must stay $C2)"
[ -z "$(_ref "$A" "")" ]            || _fail "?.. minted a trunk ref"
[ "$(cat "$A/f.txt")" = "two" ]     || _fail "?.. touched the wt bytes"

pass
