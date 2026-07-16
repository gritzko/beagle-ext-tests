#!/bin/sh
# test/post/wt-target-none — POST-027 cell 1b/4-i: `post //nosuch` where the
# authority anchors NO local worktree must REFUSE (the WTNONE guard,
# advanceWorktree post.js:318-367 at :324) and mutate NOTHING anywhere.
# Spec: /wiki/POST.mkd §"Summary of invocation patterns" row 4 — a `//wt`
# target advances ANOTHER tree; an absent target has nothing to advance.
#
# NOTE on the refusal code: post.js:324's `WTNONE` is SHADOWED today — the
# resolveHash(ctx, `//nosuch`) call one line above (post.js:322, step 4/5.5)
# throws `NAVNONE: no worktree //nosuch` first, so the wtdir guard is never
# reached.  Both codes are the SAME "anchors no local worktree" refusal; this
# case pins the SPEC behaviour (loud refusal + zero mutation) and accepts
# either spelling rather than the dead guard's literal code word.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/wt-target-none
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/wt-target-none: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/wt-target-none: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=wt-target-none
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

# base helper: the worktree's OWN cur row (wtlog.js curTip) — the jab-script
# probe test/post/wt-target uses; never od/grep `.be` raw.
_base() {   # _base DIR
    cat > "$WORK/.base.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const c=wtlog.open(info).curTip();
const u=utf8.Encode(((c&&c.sha)||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.base.js" "$1" "$BEDIR" 2>/dev/null
}

# --- worktree A: bootstrap a fresh store, commit c1 -------------------------
mkdir -p "$WORKD/A/.be"
( cd "$WORKD/A" && printf 'A\n' > a.txt && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "A bootstrap post failed"
A_TIP=$(_base "$WORKD/A")
[ -n "$A_TIP" ] || _fail "fixture: A has no cur tip"

A_WTLOG_BEFORE=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)
WORKD_LS_BEFORE=$(ls "$WORKD")

# --- the op under test: `post //nosuch` — no such worktree anywhere ---------
RC=0
( cd "$WORKD/A" && "$JABC" post '//nosuch' ) >"$WORK/post.out" 2>"$WORK/post.err" || RC=$?

[ "$RC" -ne 0 ] || { echo "  stdout: $(cat "$WORK/post.out")" >&2; \
    _fail "post //nosuch SUCCEEDED — an absent target must refuse"; }
# The no-worktree refusal class: WTNONE (post.js:324) or the shadowing
# NAVNONE from resolveHash (post.js:322) — either must NAME the refusal.
grep -qE 'WTNONE|NAVNONE' "$WORK/post.err" \
    || { cat "$WORK/post.err" >&2; \
         _fail "refusal is not the WTNONE/NAVNONE no-worktree class"; }
grep -qi 'no worktree\|anchors no local worktree' "$WORK/post.err" \
    || { cat "$WORK/post.err" >&2; \
         _fail "refusal does not say the worktree is absent"; }

# NOTHING mutated anywhere:
#  * A's own cur and wtlog untouched,
#  * no `nosuch` dir (or anything else) minted under work/.
[ "$(_base "$WORKD/A")" = "$A_TIP" ] || _fail "post //nosuch moved A's own cur"
A_WTLOG_AFTER=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)
[ "$A_WTLOG_AFTER" = "$A_WTLOG_BEFORE" ] \
    || _fail "post //nosuch mutated A's wtlog ($A_WTLOG_BEFORE -> $A_WTLOG_AFTER)"
[ "$(ls "$WORKD")" = "$WORKD_LS_BEFORE" ] \
    || _fail "post //nosuch minted something under work/: $(ls "$WORKD")"
[ ! -e "$WORKD/nosuch" ] || _fail "post //nosuch created the target dir"

pass
