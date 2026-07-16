#!/bin/sh
# test/get/gitlink-fork — DIS-072: `jab get //WT/sub` (here `///sub`, the main
# tree's sub) from an empty cell must fork the SUB's own repo pinned at the
# parent's GITLINK, never the parent project.  resolve_hash returns rpath="sub"
# + otype "commit" + ohash=<gitlink target> for such an operand; get's
# handleWtSeed used chash (the PARENT's own cur) + the parent shard, so
# `jab get ///be` cloned the whole parent project (and died in idxmaint).
#
# RED before the fix: DEST gets the PARENT's files (TOP.c), not the sub's,
# and tracks `///sub#<parent chash>`.
# GREEN after: DEST gets the SUB's tree (S.c only), tracking `///sub#<pin>`.
# Also: an OCCUPIED cell tracking another shard refuses loudly (GETCELL).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/get/gitlink-fork
_ROOT=$(cd "$_CASE/../.." && pwd)                # test/
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "get/gitlink-fork: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "get/gitlink-fork: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/get/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# jab's upward scan resolves the extension via this `jsrc` shard symlink.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true

# URI-016: bound the project-root climb ABOVE $PROJ (wt-operand pattern).
export BE_ROOT="$WORK"

# the newest `#<40hex>` fragment in a wtlog dump (assertion probe only).
wtlog_tip() { od -An -c "$1" | tr -d ' \n' | grep -oE '#[0-9a-f]{40}' | tail -1 | tr -d '#'; }

# --- the SUB's own store (a separate colocated primary) --------------------
SUBSTORE="$WORK/storeS"
mkdir -p "$SUBSTORE/.be"
( cd "$SUBSTORE" && printf 'sub payload\n' > S.c && "$BE" post 'sub initial' ) \
    >/dev/null 2>&1 || _fail "could not seed the sub store"
STIP=$(wtlog_tip "$SUBSTORE/.be/wtlog")
[ -n "$STIP" ] || _fail "no sub tip sha"

# --- the PROJECT ROOT (main tree) with the sub mounted + gitlinked ---------
PROJ="$WORK/proj"
mkdir -p "$PROJ/.be" "$PROJ/work"
printf 'top v1\n' > "$PROJ/TOP.c"
( cd "$PROJ" && "$BE" post 'main tree' ) >/dev/null 2>&1 || _fail "could not seed the main tree"

mkdir -p "$PROJ/sub"
( cd "$PROJ/sub" && "$JABC" get "file:$SUBSTORE/.be#$STIP" ) >/dev/null 2>&1 \
    || _fail "could not mount the sub"
# seed the `put sub#<pin>` gitlink row (jab has no CLI spelling for a raw pin).
cat > "$WORK/.pinrow.js" <<'EOF'
const ulog = require(process.argv[2] + "/shared/ulog.js");
ulog.append(process.argv[4], [{ verb: "put",
  uri: URI.make(undefined, undefined, process.argv[3], undefined, process.argv[5]) }]);
EOF
"$JABC" "$WORK/.pinrow.js" "$BEDIR" "sub" "$PROJ/.be/wtlog" "$STIP" >/dev/null 2>&1 || true
( cd "$PROJ" && "$BE" post 'mount sub' ) >/dev/null 2>&1 || _fail "could not commit the gitlink"

# --- the repro: an EMPTY cell forks the main tree's SUB --------------------
DEST="$PROJ/work/dest"
mkdir -p "$DEST"
RC=0
( cd "$DEST" && "$JABC" get "///sub" ) >"$WORK/get.out" 2>"$WORK/get.err" || RC=$?
[ "$RC" = 0 ] || { cat "$WORK/get.err" >&2; _fail "jab get ///sub exit=$RC"; }

[ -f "$DEST/S.c" ] || _fail "DEST missing S.c — the SUB's tree was not forked"
[ "$(cat "$DEST/S.c")" = "sub payload" ] || _fail "DEST/S.c has the wrong content"
[ ! -e "$DEST/TOP.c" ] || _fail "DEST has TOP.c — the PARENT project was cloned (the DIS-072 bug)"
[ -e "$DEST/.be" ] || _fail "DEST has no .be anchor — no clone landed"

# tracks the operand pinned at the GITLINK target, not the parent's cur.
od -An -c "$DEST/.be" | tr -d ' \n' | grep -q "///sub#$STIP" \
    || _fail "DEST does not track ///sub#$STIP (gitlink pin): $(cat "$DEST/.be")"

# --- occupied cell: a mismatched fork refuses loudly (GETCELL) -------------
OTHER="$PROJ/work/other"
mkdir -p "$OTHER"
MAINSHA=$(wtlog_tip "$PROJ/.be/wtlog")
( cd "$OTHER" && "$JABC" get "file:$PROJ/.be#$MAINSHA" ) >/dev/null 2>&1 \
    || _fail "could not clone the other cell"
RC=0
( cd "$DEST" && "$JABC" get "//other" ) >"$WORK/get2.out" 2>"$WORK/get2.err" || RC=$?
[ "$RC" != 0 ] || _fail "get //other into the sub-tracking cell did NOT refuse"
grep -q "GETCELL" "$WORK/get2.err" "$WORK/get2.out" 2>/dev/null \
    || _fail "no GETCELL refusal: $(cat "$WORK/get2.err")"
[ ! -e "$DEST/TOP.c" ] || _fail "the refused get still wrote parent files"

echo "PASS [$NAME]"
