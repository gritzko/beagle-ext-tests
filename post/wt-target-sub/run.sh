#!/bin/sh
# test/post/wt-target-sub — POST-036: `post //X/sub` (BARE, no trailing slash)
# must FF-advance the SUB's own base, exactly as the entered form `//X/sub/`
# does.  resolve_hash's frame() re-anchors a bare mount root to its PARENT (the
# de-jure gitlink reading), so `rh.chash` is the PARENT wt's base and only
# `rh.ohash`/`rpath` carry the sub — advanceWorktree fed that parent sha into
# the FF verdict (and into the 3-way `oldTip`), so a strictly-behind sub read
# "unrelated to cur".  Get already re-resolves the entered form in that arm
# (handleWtSeed, DIS-072); post now mirrors it.
#
# RED before the fix: `post //X/dog` -> "`//X/dog` is unrelated to cur", dog's
# base unmoved.  GREEN after: dog's base is A's tip (and `//X/dog/` still is).
#
# Fixture (the test/post/wt-target + test/get/gitlink-fork patterns): SRC is the
# project root, so `SRC/work/NAME` IS `//NAME`.  A is the dog worktree; X is a
# SECOND worktree with a clone of A mounted at `X/dog` + a committed gitlink
# pin, so `//X/dog` is a bare mount root whose parent frame is X's own store.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/wt-target-sub
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/wt-target-sub: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/wt-target-sub: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=wt-target-sub
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [post/$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [post/$NAME]"; }

. "$_ROOT/lib/repo-setup.sh"

# URI-016: SRC is the PROJECT ROOT (its own `.be/` anchor); `SRC/work/NAME` IS
# `//NAME`.  BE_ROOT confines the climb above SRC (test/post/wt-target pattern).
SRC="$WORK/src"
WORKD=$(rs_work_root "$SRC")
ln -sfn "$BEDIR" "$SRC/jsrc"
export BE_ROOT="$WORK"

# base helper: the worktree's OWN cur row (wtlog.js curTip) — what an advance
# must move, and what resolve_hash step 5.5 reads (test/post/wt-target's probe).
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

# --- worktree A: the dog repo, commit d1 ------------------------------------
mkdir -p "$WORKD/A/.be"
( cd "$WORKD/A" && printf 'dog 1\n' > d.txt && "$BE" post '#d1' ) >/dev/null 2>&1 \
    || _fail "A bootstrap post failed"
D0=$(_base "$WORKD/A")
[ -n "$D0" ] || _fail "fixture: A has no cur tip"

# --- worktree X: its OWN store, with A mounted as the sub `dog` --------------
mkdir -p "$WORKD/X/.be"
( cd "$WORKD/X" && printf 'x 1\n' > x.txt && "$BE" post '#x1' ) >/dev/null 2>&1 \
    || _fail "X bootstrap post failed"
mkdir -p "$WORKD/X/dog"
( cd "$WORKD/X/dog" && "$JABC" get "file://$WORKD/A/.be#$D0" ) >/dev/null 2>&1 \
    || _fail "could not mount X/dog"
[ "$(_base "$WORKD/X/dog")" = "$D0" ] || _fail "fixture: X/dog is not at A's d1 tip"

# the `put dog#<pin>` gitlink row (jab has no CLI spelling for a raw pin) —
# committed, so a BARE `//X/dog` resolves the parent frame + otype "commit".
cat > "$WORK/.pinrow.js" <<'EOF'
const ulog = require(process.argv[2] + "/shared/ulog.js");
ulog.append(process.argv[4], [{ verb: "put",
  uri: URI.make(undefined, undefined, process.argv[3], undefined, process.argv[5]) }]);
EOF
"$JABC" "$WORK/.pinrow.js" "$BEDIR" "dog" "$WORKD/X/.be/wtlog" "$D0" >/dev/null 2>&1 || true
( cd "$WORKD/X" && "$BE" post '#mount dog' ) >/dev/null 2>&1 \
    || _fail "could not commit the X/dog gitlink"
X_BASE=$(_base "$WORKD/X")
[ -n "$X_BASE" ] && [ "$X_BASE" != "$D0" ] || _fail "fixture: X's base is not its own"

# --- A advances past the sub's base: d2 (an FF-able divergence) -------------
( cd "$WORKD/A" && printf 'dog 2\n' > d.txt && "$BE" put d.txt && "$BE" post '#d2' ) \
    >/dev/null 2>&1 || _fail "A d2 post failed"
D1=$(_base "$WORKD/A")
[ "$D1" != "$D0" ] || _fail "fixture: A did not advance past the sub's base"

A_WTLOG_BEFORE=$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)

# --- the op under test: BARE `post //X/dog` FF-advances the SUB -------------
RC=0
( cd "$WORKD/A" && "$JABC" post "//X/dog" ) >"$WORK/bare.out" 2>"$WORK/bare.err" || RC=$?
SUB_BASE=$(_base "$WORKD/X/dog")

if [ "$RC" -ne 0 ] || [ "$SUB_BASE" != "$D1" ]; then
    echo "post/wt-target-sub: RED (rc=$RC) — bare 'post //X/dog' did not FF the sub" >&2
    echo "  stdout: $(cat "$WORK/bare.out")" >&2
    echo "  stderr: $(cat "$WORK/bare.err")" >&2
    echo "  sub base before=$D0 after=$SUB_BASE want=$D1 (X's own base=$X_BASE)" >&2
    _fail "bare //X/dog did not FF-advance the sub (POST-036)"
fi
[ "$(_base "$WORKD/X")" = "$X_BASE" ] \
    || _fail "the sub advance moved X's OWN base (must touch the sub only)"
[ "$(wc -l < "$WORKD/A/.be/wtlog" 2>/dev/null || echo 0)" = "$A_WTLOG_BEFORE" ] \
    || _fail "post //X/dog mutated A's own wtlog (cur must stay untouched)"

# --- regression: the ENTERED form `//X/dog/` keeps working -------------------
( cd "$WORKD/A" && printf 'dog 3\n' > d.txt && "$BE" put d.txt && "$BE" post '#d3' ) \
    >/dev/null 2>&1 || _fail "A d3 post failed"
D2=$(_base "$WORKD/A")
RC=0
( cd "$WORKD/A" && "$JABC" post "//X/dog/" ) >"$WORK/entered.out" 2>"$WORK/entered.err" || RC=$?
[ "$RC" = 0 ] || { cat "$WORK/entered.err" >&2; _fail "entered form //X/dog/ regressed (rc=$RC)"; }
[ "$(_base "$WORKD/X/dog")" = "$D2" ] || _fail "entered //X/dog/ did not FF the sub to $D2"

# --- a genuinely unrelated sub still refuses, naming ITS OWN base ------------
# `other` is a second, independent repo mounted in X: its base shares no
# ancestor with A's tip, so the verdict must still say unrelated — and the
# message must name the compared tree (the SUB's base), not X's.
mkdir -p "$WORKD/X/other"
( cd "$WORKD/X/other" && printf 'other\n' > o.txt && "$BE" post '#o1' ) >/dev/null 2>&1 \
    || _fail "could not seed X/other"
O0=$(_base "$WORKD/X/other")
[ -n "$O0" ] || _fail "fixture: X/other has no cur tip"
"$JABC" "$WORK/.pinrow.js" "$BEDIR" "other" "$WORKD/X/.be/wtlog" "$O0" >/dev/null 2>&1 || true
( cd "$WORKD/X" && "$BE" post '#mount other' ) >/dev/null 2>&1 \
    || _fail "could not commit the X/other gitlink"
# a parent post recurses into its subs (SUBS-056), so re-read the sub's base
# AFTER the mount commit — that is the base the refusal must name.
O0=$(_base "$WORKD/X/other")
RC=0
( cd "$WORKD/A" && "$JABC" post "//X/other" ) >"$WORK/unrel.out" 2>"$WORK/unrel.err" || RC=$?
[ "$RC" != 0 ] || _fail "post //X/other (unrelated history) did NOT refuse"
[ "$(_base "$WORKD/X/other")" = "$O0" ] || _fail "the refused post moved X/other's base"
grep -q "unrelated to cur" "$WORK/unrel.err" "$WORK/unrel.out" 2>/dev/null \
    || _fail "not the unrelated refusal: $(cat "$WORK/unrel.err")"
grep -q "$(printf '%s' "$O0" | cut -c1-8)" "$WORK/unrel.err" "$WORK/unrel.out" 2>/dev/null \
    || _fail "the refusal does not name the SUB's own base ${O0}: $(cat "$WORK/unrel.err")"

pass
