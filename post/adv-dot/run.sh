#!/bin/sh
# test/post/adv-dot — POST-027 cell 3 `?.`: the literal OWN-branch token.
# POST.mkd §"Summary of invocation patterns" cell 3 + the DIS-061 uniform
# ruling: `post '?.'` resolves to cur's OWN branch (resolveTarget post.js:254)
# and FF-moves it to cur's tip — THE standard way to advance your branch to
# the wt base.  No commit, cur untouched, the wt byte-intact.  A second
# `post '?.'` at the tip refuses POSTNONE "already at" (never the
# commit-shaped "no changes since base").
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/adv-dot
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/adv-dot: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/adv-dot: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=adv-dot
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

# ===== fixture: attached to `?feat`, one commit ahead of it =================
A="$WORKD/A"; mkdir -p "$A/.be"
( cd "$A" && printf 'one\n' > f.txt && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "A: bootstrap post c1 failed"
C1=$(_cur "$A"); [ -n "$C1" ] || _fail "A: no c1 tip"
( cd "$A" && "$JABC" post '?feat' ) >/dev/null 2>&1 \
    || _fail "A: publish ?feat failed"
( cd "$A" && "$JABC" get '?feat' ) >/dev/null 2>&1 \
    || _fail "A: attach to ?feat failed"
( cd "$A" && printf 'two\n' > f.txt && "$JABC" put f.txt && "$JABC" post '#c2' ) >/dev/null 2>&1 \
    || _fail "A: post c2 failed"
C2=$(_cur "$A"); [ -n "$C2" ] && [ "$C2" != "$C1" ] || _fail "A: no distinct c2 tip"
[ "$(_ref "$A" feat)" = "$C1" ] || _fail "fixture: feat not behind cur"

# ===== leg 1: `post '?.'` FFs cur's OWN branch to cur's tip ==================
_fresh "$A"
RC=0
( cd "$A" && "$JABC" post '?.' ) >"$WORK/d.out" 2>"$WORK/d.err" || RC=$?
if [ "$RC" -ne 0 ] || [ "$(_ref "$A" feat)" != "$C2" ]; then
    echo "post/adv-dot: RED (rc=$RC) — ?. did not FF cur's own branch" >&2
    echo "  stdout: $(cat "$WORK/d.out")" >&2
    echo "  stderr: $(cat "$WORK/d.err")" >&2
    echo "  feat=$(_ref "$A" feat) want=$C2" >&2
    _fail "post ?. did not FF feat to cur's tip (see above)"
fi
[ "$(_cur "$A")" = "$C2" ]      || _fail "?. moved cur (must stay $C2)"
[ "$(cat "$A/f.txt")" = "two" ] || _fail "?. touched the wt bytes"

# ===== leg 2: `post '?.'` again at the tip refuses POSTNONE "already at" ====
RC=0
( cd "$A" && "$JABC" post '?.' ) >"$WORK/d2.out" 2>"$WORK/d2.err" || RC=$?
[ "$RC" -ne 0 ] \
    || _fail "at-tip ?. advance did not refuse: $(cat "$WORK/d2.out")"
grep -q "already at cur's tip" "$WORK/d2.err" \
    || _fail "at-tip ?. refusal lacks the clear 'already at' report: $(cat "$WORK/d2.err")"
if grep -q "no changes since base" "$WORK/d2.err"; then
    _fail "at-tip ?. reports the commit-shaped 'no changes since base': $(cat "$WORK/d2.err")"
fi
[ "$(_ref "$A" feat)" = "$C2" ] || _fail "at-tip ?. refusal moved feat"

pass
