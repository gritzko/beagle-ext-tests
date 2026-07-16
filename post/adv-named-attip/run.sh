#!/bin/sh
# test/post/adv-named-attip — POST-027 cell 3-ii: an EXPLICIT named advance
# (`post '?name'`) whose target is exactly AT cur's tip.  POST.mkd §"Summary
# of invocation patterns" cell 3: "FF-move that ref to cur's tip, no commit,
# cur untouched" — nothing to move here, so it refuses POSTNONE with the
# CLEAR "already at" report (advanceBranch post.js:284), NEVER the
# commit-shaped "no changes since base" (that is the commit arm's refusal;
# the bare-track variant of this cell lives in post/bare-advance).  The wt
# and the ref stay byte-intact.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/adv-named-attip
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/adv-named-attip: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/adv-named-attip: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=adv-named-attip
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

# ===== fixture: feat published exactly AT cur's tip ==========================
# A bootstraps c1, publishes `?feat` at c1; the wt stays attached to TRUNK —
# this is the EXPLICIT-named entry, not the bare-track arm.
A="$WORKD/A"; mkdir -p "$A/.be"
( cd "$A" && printf 'one\n' > f.txt && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "A: bootstrap post c1 failed"
C1=$(_cur "$A"); [ -n "$C1" ] || _fail "A: no c1 tip"
( cd "$A" && "$JABC" post '?feat' ) >/dev/null 2>&1 \
    || _fail "A: publish ?feat at c1 failed"
[ "$(_ref "$A" feat)" = "$C1" ] || _fail "fixture: feat != cur's tip"

# ===== the at-tip explicit advance refuses POSTNONE "already at" ============
RC=0
( cd "$A" && "$JABC" post '?feat' ) >"$WORK/a.out" 2>"$WORK/a.err" || RC=$?
[ "$RC" -ne 0 ] \
    || _fail "at-tip explicit ?feat advance did not refuse: $(cat "$WORK/a.out")"
grep -q "already at cur's tip" "$WORK/a.err" \
    || _fail "at-tip explicit ?feat refusal lacks the clear 'already at' report: $(cat "$WORK/a.err")"
if grep -q "no changes since base" "$WORK/a.err"; then
    _fail "at-tip explicit ?feat reports the commit-shaped 'no changes since base': $(cat "$WORK/a.err")"
fi
# byte-intact: neither the ref nor the wt moved.
[ "$(_ref "$A" feat)" = "$C1" ] || _fail "at-tip refusal moved feat"
[ "$(_cur "$A")" = "$C1" ]      || _fail "at-tip refusal moved cur"
[ "$(cat "$A/f.txt")" = "one" ] || _fail "at-tip refusal touched the wt bytes"

pass
