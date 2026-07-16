#!/bin/sh
# test/post/wt-target-self — POST-027 cell 4-self: an explicit `post //A` run
# from INSIDE A itself must refuse `POSTNONE: ... is this worktree`
# (advanceWorktree post.js:318-367, the self guard at :326-327; selfWorktree
# :388-395).  Spec: /wiki/POST.mkd §"Summary of invocation patterns" row 4 —
# `//wt` targets advance OTHER trees; a tree cannot be its own post target.
#
# RED today: the refusal is UNREACHABLE for the explicit operand.  core/loop.js
# authorityRepo resolves arg0 `//A` and — since the cwd is ALREADY inside A —
# consumes it as the run anchor (nav context), so post runs BARE: it falls into
# the advanceTrack/branch arm and (on this fixture, a bootstrapped wt with no
# track) exits 0 after FF-ing the trunk ref to cur's tip — a straight-up
# MUTATION where the spec demands a POSTNONE refusal.  The `//self` operand
# must reach post.js intact (the same DIS-062 classifier ground as
# test/post/wt-target) for the :326 guard to fire.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/wt-target-self
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/wt-target-self: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/wt-target-self: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=wt-target-self
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

# --- worktree A: bootstrap a fresh store, commit c1 --------------------------
mkdir -p "$WORKD/A/.be"
( cd "$WORKD/A" && printf 'A\n' > a.txt && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "A bootstrap post failed"
A_TIP=$(_base "$WORKD/A")
[ -n "$A_TIP" ] || _fail "fixture: A has no cur tip"

A_WTLOG_BEFORE=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)

# --- the op under test: `post //A` from inside A itself ----------------------
RC=0
( cd "$WORKD/A" && "$JABC" post '//A' ) >"$WORK/post.out" 2>"$WORK/post.err" || RC=$?

if [ "$RC" = 0 ]; then
    echo "post/wt-target-self: RED — 'post //A' from inside A SUCCEEDED (rc=0)" >&2
    echo "  stdout: $(cat "$WORK/post.out")" >&2
    echo "  stderr: $(cat "$WORK/post.err")" >&2
    echo "post/wt-target-self: EXPECTED red — core/loop.js authorityRepo eats" >&2
    echo "  the arg0 //A as the run anchor (cwd is inside A), post runs BARE" >&2
    echo "  and FFs the trunk ref instead of the POSTNONE 'is this worktree'" >&2
    echo "  refusal (post.js:326-327, never reached)." >&2
    _fail "post //A did not refuse (see above)"
fi
grep -q 'is this worktree' "$WORK/post.err" \
    || { cat "$WORK/post.err" >&2; \
         _fail "refusal does not say 'is this worktree'"; }

# Nothing moved: A's cur and wtlog untouched.
[ "$(_base "$WORKD/A")" = "$A_TIP" ] || _fail "post //A moved A's own cur"
A_WTLOG_AFTER=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)
[ "$A_WTLOG_AFTER" = "$A_WTLOG_BEFORE" ] \
    || _fail "post //A mutated A's wtlog ($A_WTLOG_BEFORE -> $A_WTLOG_AFTER)"

pass
