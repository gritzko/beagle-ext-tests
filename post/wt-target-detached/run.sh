#!/bin/sh
# test/post/wt-target-detached — POST-027 cell 4-detached: a DETACHED target
# stays detached across a `post //B` advance.  DIS-075 row shape: the advance
# row appended to B's OWN wtlog must be the bare-hash `#<tip>` (fragment only,
# query slot ABSENT) and never the trunk-shaped `?#<tip>` (present-empty
# query = attached-to-trunk).  advanceWorktree post.js:318-367 — the
# attachedBranch/detached gate at :351-360 picks the row's query slot.
# Spec: /wiki/POST.mkd §"Summary of invocation patterns" row 4 (merge the
# target's files, then FF its base — the branch tie, or its absence, is the
# target's own and is preserved).
#
# Fixture: B clones A at c1, then DETACHES via `get ?<sha>` (the
# test/get/detach D2 fixture — records the detached `#<40hex>` row); A commits
# c2; `(cd A && jab post //B)` FFs B.  The appended post row is probed via a
# jab script over shared/wtlog.js rows (the _base pattern) — never od/grep
# on `.be` raw.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/wt-target-detached
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/wt-target-detached: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/wt-target-detached: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=wt-target-detached
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

# _lastpost DIR — the RECENTMOST `post` row's uri slots, printed as
# `QABSENT F=<fragment>` (detached shape) or `Q=<query> F=<fragment>`
# (attached / trunk `?` shape).  Reads shared/wtlog.js rows — the row shapes
# DIS-075 defines — through the same jab-script probe channel as _base.
_lastpost() {   # _lastpost DIR
    cat > "$WORK/.lastpost.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const wtl=wtlog.open(info);
let last;
for (const r of wtl.rows) if (r.verb==="post") last=r;
let s;
if (!last) s="NOROW";
else s=(last.uri.query===undefined?"QABSENT":("Q="+last.uri.query))
       +" F="+(last.uri.fragment||"");
const u=utf8.Encode(s+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.lastpost.js" "$1" "$BEDIR" 2>/dev/null
}

# --- worktree A: bootstrap a fresh store, commit c1 ---------------------------
mkdir -p "$WORKD/A/.be"
( cd "$WORKD/A" && printf 'A\n' > a.txt && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "A bootstrap post failed"
C1=$(_base "$WORKD/A")

# --- worktree B: clone at c1, then DETACH there (test/get/detach D2) ----------
mkdir -p "$WORKD/B"
( cd "$WORKD/B" && "$BE" get "file://$WORKD/A/.be#$C1" ) >/dev/null 2>&1 \
    || _fail "B clone failed"
( cd "$WORKD/B" && "$JABC" get "?$C1" ) >/dev/null 2>&1 \
    || _fail "B detach (get ?<sha>) failed"
[ "$(_base "$WORKD/B")" = "$C1" ] || _fail "fixture: detached B base != c1"

# --- A commits c2 past B ------------------------------------------------------
( cd "$WORKD/A" && printf 'A2\n' > a.txt && "$JABC" put a.txt && "$JABC" post '#c2' ) >/dev/null 2>&1 \
    || _fail "A c2 post failed"
A_TIP=$(_base "$WORKD/A")
[ "$A_TIP" != "$C1" ] || _fail "fixture: A did not advance past c1"

# --- the op under test: `post //B` FFs the DETACHED B -------------------------
RC=0
( cd "$WORKD/A" && "$JABC" post '//B' ) >"$WORK/post.out" 2>"$WORK/post.err" || RC=$?
[ "$RC" = 0 ] || { echo "  stderr: $(cat "$WORK/post.err")" >&2; \
                   echo "  stdout: $(cat "$WORK/post.out")" >&2; \
                   _fail "post //B onto the detached B exit $RC"; }

# 1. B FF-advanced (base + files).
[ "$(_base "$WORKD/B")" = "$A_TIP" ] \
    || _fail "post //B did not FF the detached B (got $(_base "$WORKD/B") want $A_TIP)"
[ "$(cat "$WORKD/B/a.txt")" = "A2" ] \
    || _fail "post //B left B/a.txt stale (got '$(cat "$WORKD/B/a.txt")' want 'A2')"

# 2. THE cell assert (DIS-075): the advance row is the bare-hash `#<tip>` —
#    fragment = the new tip, query slot ABSENT; never trunk-shaped `?#<tip>`.
ROW=$(_lastpost "$WORKD/B")
[ "$ROW" != "NOROW" ] || _fail "no post row appended to B's wtlog"
case "$ROW" in
    "QABSENT F=$A_TIP") : ;;                     # the detached `#<tip>` shape
    "Q="*)  _fail "detached B re-ATTACHED: advance row is '?'-shaped ($ROW) — want bare #$A_TIP" ;;
    *)      _fail "advance row has the wrong shape ($ROW) — want QABSENT F=$A_TIP" ;;
esac

echo "ok   post //B advanced the detached B with a bare #<tip> row ($ROW)"
pass
