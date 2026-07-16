#!/bin/sh
# test/post/adv-trunk-states — POST-027 cell 3 `?`: the TRUNK advance's
# refuse ladder.  POST.mkd §"Summary of invocation patterns" cell 3 (`?` is
# trunk) + cell 1a's ladder: at cur's tip → POSTNONE "already at"; trunk
# already PAST cur (contains it) → POSTNONE "already contains"; trunk
# DIVERGED from cur → POSTNOFF.  Every refusal leaves the wt byte-intact
# (only behind-FF, the green arm, is pinned elsewhere — post/slots).
# Leg order: at-tip, diverged, ahead/contains (the RED one last, so the
# green legs still run).
# RED today (ahead leg): advanceBranch's FF gate (post.js:287, POSTNOFF
# "not an ancestor of cur") fires BEFORE the contains arm (post.js:291), so
# a trunk that contains cur refuses POSTNOFF and the POSTNONE "already
# contains" arm is unreachable dead code.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/adv-trunk-states
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/adv-trunk-states: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/adv-trunk-states: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=adv-trunk-states
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
# shared/store.js resolveRef — not a re-implementation).  "" is trunk.
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
# mint trunk at c1 (the green FF-from-nothing arm — setup, not the SUT).
( cd "$A" && "$JABC" post '?' ) >/dev/null 2>&1 \
    || _fail "A: mint trunk at c1 failed"
[ "$(_ref "$A" "")" = "$C1" ] || _fail "fixture: trunk not at c1"

# ===== leg 1: trunk AT cur's tip → POSTNONE "already at" =====================
RC=0
( cd "$A" && "$JABC" post '?' ) >"$WORK/t1.out" 2>"$WORK/t1.err" || RC=$?
[ "$RC" -ne 0 ] \
    || _fail "at-tip trunk advance did not refuse: $(cat "$WORK/t1.out")"
grep -q "already at cur's tip" "$WORK/t1.err" \
    || _fail "at-tip trunk refusal lacks the clear 'already at' report: $(cat "$WORK/t1.err")"
[ "$(_ref "$A" "")" = "$C1" ]   || _fail "at-tip refusal moved trunk"
[ "$(_cur "$A")" = "$C1" ]      || _fail "at-tip refusal moved cur"
[ "$(cat "$A/f.txt")" = "one" ] || _fail "at-tip refusal touched the wt bytes"

# ===== advance trunk to c2 (setup for the diverged + ahead legs) =============
( cd "$A" && printf 'two\n' > f.txt && "$JABC" put f.txt && "$JABC" post '#c2' ) >/dev/null 2>&1 \
    || _fail "A: post c2 failed"
C2=$(_cur "$A"); [ -n "$C2" ] && [ "$C2" != "$C1" ] || _fail "A: no distinct c2 tip"
( cd "$A" && "$JABC" post '?' ) >/dev/null 2>&1 \
    || _fail "A: FF trunk to c2 failed"
[ "$(_ref "$A" "")" = "$C2" ] || _fail "fixture: trunk not at c2"

# ===== leg 2: trunk DIVERGED from cur → POSTNOFF =============================
# Detach at c1 and commit d1 — cur (d1) and trunk (c2) now sit on divergent
# lines off the common base c1 (get/detach's detach fixture, a detached
# commit hops cur only; DIS-076: no ref moves).
_fresh "$A"
( cd "$A" && "$JABC" get "?$C1" ) >/dev/null 2>&1 \
    || _fail "A: detach at c1 failed"
[ "$(_cur "$A")" = "$C1" ] || _fail "fixture: cur != c1 after the detach"
( cd "$A" && printf 'div\n' > f.txt && "$JABC" put f.txt && "$JABC" post '#d1' ) >/dev/null 2>&1 \
    || _fail "A: detached post d1 failed"
D1=$(_cur "$A"); [ -n "$D1" ] && [ "$D1" != "$C2" ] || _fail "A: no divergent d1 tip"
[ "$(_ref "$A" "")" = "$C2" ] || _fail "fixture: the detached d1 commit moved trunk"

_fresh "$A"
RC=0
( cd "$A" && "$JABC" post '?' ) >"$WORK/t2.out" 2>"$WORK/t2.err" || RC=$?
[ "$RC" -ne 0 ] \
    || _fail "diverged trunk advance did not refuse: $(cat "$WORK/t2.out")"
grep -q "can not be fast-forwarded" "$WORK/t2.err" \
    || _fail "diverged trunk advance refused but not the non-FF report: $(cat "$WORK/t2.err")"
[ "$(_ref "$A" "")" = "$C2" ]   || _fail "diverged refusal moved trunk"
[ "$(_cur "$A")" = "$D1" ]      || _fail "diverged refusal moved cur"
[ "$(cat "$A/f.txt")" = "div" ] || _fail "diverged refusal touched the wt bytes"

# ===== leg 3: trunk CONTAINS cur (ahead) → POSTNONE "already contains" =======
# Re-attach to trunk PINNED at c1 — cur=c1, trunk=c2 ⊃ cur.
_fresh "$A"
( cd "$A" && "$JABC" get "?#$C1" ) >/dev/null 2>&1 \
    || _fail "A: re-attach trunk pinned at c1 failed"
[ "$(_cur "$A")" = "$C1" ]      || _fail "fixture: cur != c1 after the pinned get"
[ "$(_ref "$A" "")" = "$C2" ]   || _fail "fixture: trunk not at c2"
[ "$(cat "$A/f.txt")" = "one" ] || _fail "fixture: f.txt not at c1's bytes"

_fresh "$A"
RC=0
( cd "$A" && "$JABC" post '?' ) >"$WORK/t3.out" 2>"$WORK/t3.err" || RC=$?
[ "$RC" -ne 0 ] \
    || _fail "containing trunk advance did not refuse: $(cat "$WORK/t3.out")"
[ "$(_ref "$A" "")" = "$C2" ]   || _fail "containing refusal moved trunk"
[ "$(_cur "$A")" = "$C1" ]      || _fail "containing refusal moved cur"
[ "$(cat "$A/f.txt")" = "one" ] || _fail "containing refusal touched the wt bytes"
if ! grep -q "already contains cur's tip" "$WORK/t3.err"; then
    echo 'post/adv-trunk-states: RED — a trunk that already contains cur must refuse "already contains" (POST.mkd cell 1a: already at/past it), got:' >&2
    echo "  stderr: $(cat "$WORK/t3.err")" >&2
    _fail 'containing trunk advance refused with the wrong class (want POSTNONE "already contains")'
fi

pass
