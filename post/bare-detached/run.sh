#!/bin/sh
# test/post/bare-detached — POST-027 cell 1c: a bare `jab post` on a CLEAN
# DETACHED worktree.  POST.mkd §"Summary of invocation patterns" cell 1:
# "detached: refused (POSTNONE), no track to advance" — the bare post is the
# ADVANCE arm and a detached wt has no track, so it must refuse
# POSTNONE-class: no commit is created, no ref moves, the wtlog and the wt
# bytes stay identical.  (The patch exception — an active absorbed patch
# reuses its message — is post/bare-patch-reuse's cell.)  The detach fixture
# is get/detach's: `get '?<sha>'` writes the detached `#<sha>` row.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/bare-detached
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/bare-detached: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/bare-detached: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=bare-detached
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
# the wt's wtlog path via the SAME `jab refs` report (byte-intact probe).
_wtlog() { ( cd "$1" && "$JABC" refs ) 2>/dev/null | sed -n 's/^be: *//p'; }

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

# ===== fixture: a clean wt DETACHED at c1 (trunk ref parked at c2) ===========
A="$WORKD/A"; mkdir -p "$A/.be"
( cd "$A" && printf 'one\n' > f.txt && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "A: bootstrap post c1 failed"
C1=$(_cur "$A"); [ -n "$C1" ] || _fail "A: no c1 tip"
( cd "$A" && printf 'two\n' > f.txt && "$JABC" put f.txt && "$JABC" post '#c2' ) >/dev/null 2>&1 \
    || _fail "A: post c2 failed"
C2=$(_cur "$A"); [ -n "$C2" ] && [ "$C2" != "$C1" ] || _fail "A: no distinct c2 tip"
( cd "$A" && "$JABC" post '?' ) >/dev/null 2>&1 \
    || _fail "A: mint trunk at c2 failed"
[ "$(_ref "$A" "")" = "$C2" ] || _fail "fixture: trunk not at c2"
# detach at c1 (get/detach: `get ?<sha>` writes the detached `#<sha>` row).
_fresh "$A"
( cd "$A" && "$JABC" get "?$C1" ) >/dev/null 2>&1 \
    || _fail "A: detach at c1 failed"
[ "$(_cur "$A")" = "$C1" ]      || _fail "fixture: cur != c1 after the detach"
[ "$(cat "$A/f.txt")" = "one" ] || _fail "fixture: the detach did not rewind f.txt (tree not clean)"
WTLOG=$(_wtlog "$A"); [ -n "$WTLOG" ] && [ -f "$WTLOG" ] || _fail "fixture: no wtlog path from jab refs"
LOG0=$(wc -c < "$WTLOG")

# ===== the SUT: a bare post on the clean detached wt must refuse =============
_fresh "$A"
RC=0
( cd "$A" && "$JABC" post ) >"$WORK/a.out" 2>"$WORK/a.err" || RC=$?
[ "$RC" -ne 0 ] \
    || _fail "bare post on a clean detached wt did not refuse: $(cat "$WORK/a.out")"
grep -q "no changes since base" "$WORK/a.err" \
    || _fail "detached bare post refused but not no-op-class: $(cat "$WORK/a.err")"
# no commit created, no ref moved, the wt + wtlog byte-intact.
[ "$(_cur "$A")" = "$C1" ]      || _fail "detached bare post moved cur ($C1 -> $(_cur "$A"))"
[ "$(_ref "$A" "")" = "$C2" ]   || _fail "detached bare post moved the trunk ref"
[ "$(cat "$A/f.txt")" = "one" ] || _fail "detached bare post touched the wt bytes"
LOG1=$(wc -c < "$WTLOG")
[ "$LOG1" = "$LOG0" ] \
    || _fail "detached bare post mutated the wtlog ($LOG0 -> $LOG1 bytes)"

pass
