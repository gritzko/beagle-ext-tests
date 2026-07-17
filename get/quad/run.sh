#!/bin/sh
# test/get — BRO-030: the unified quad status report (wiki/Status.mkd,
# shared/quad.js via view/quadrender.js) is the DEFAULT `jab get` report (no
# flag): `<date7> <quad4> <path>` file rows for the paths THIS get wrote, plus
# the commit ahead/behind rows in the same vocabulary (RED until the flip lands).
#
# Fixture (the wt-operand scaffold): ONE store, `//srcwt` a secondary anchor
# under the project's work/, `dest` a `//srcwt` clone.  srcwt then ADVANCES
# (ticket.txt v2, commit c3), leaving dest BEHIND its track.
#  1) scoped `get --quad //srcwt/ticket.txt` (cherry-pick — base does NOT
#     move): the report shows the track-side commit as `o...` and the picked
#     file as `v..v` (track advanced, wt carries the picked bytes as dirt).
#  2) bare `get --quad` (sync to the track): base catches up, the pick is
#     absorbed — the report goes SILENT (no `o...`, no `v..v` rows after).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/get/quad
_ROOT=$(cd "$_CASE/../.." && pwd)                # test/
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "get/quad: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "get/quad: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/get/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# jab's upward be/-scan resolves the extension via this `jsrc` shard symlink.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true

# URI-016: bound the project-root climb ABOVE $PROJ (wt-operand pattern).
export BE_ROOT="$WORK"

# the newest `#<40hex>` fragment in a wtlog dump (assertion/setup probe only).
wtlog_tip() { od -An -c "$1" | tr -d ' \n' | grep -oE '#[0-9a-f]{40}' | tail -1 | tr -d '#'; }

# --- the scratch project: ONE store, worktrees CLONE it --------------------
PROJ="$WORK/proj"
mkdir -p "$PROJ/.be" "$PROJ/work"
printf 'readme\n' > "$PROJ/readme.txt"
( cd "$PROJ" && "$BE" post 'main tree' ) >/dev/null 2>&1 || _fail "could not seed the main tree"
MAIN_SHA=$(wtlog_tip "$PROJ/.be/wtlog")
[ -n "$MAIN_SHA" ] || _fail "no main-tree tip sha"

# srcwt = //srcwt: a clone of the shared store, advanced with ticket.txt (c2).
SRC="$PROJ/work/srcwt"
mkdir -p "$SRC"
( cd "$SRC" && "$JABC" get "file:$PROJ/.be#$MAIN_SHA" ) >/dev/null 2>&1 \
    || _fail "could not clone srcwt"
printf 'ticket work\n' > "$SRC/ticket.txt"
( cd "$SRC" && "$JABC" put ticket.txt && "$JABC" post 'ticket work' ) >/dev/null 2>&1 \
    || _fail "could not advance srcwt"

# dest: a `//srcwt` clone (tracks the worktree URI at its c2 rev).
DEST="$PROJ/work/dest"
mkdir -p "$DEST"
( cd "$DEST" && "$JABC" get "//srcwt" ) >/dev/null 2>&1 || _fail "could not clone dest"

# advance srcwt PAST dest's base: ticket.txt v2, commit c3.
printf 'ticket work v2\n' > "$SRC/ticket.txt"
( cd "$SRC" && "$JABC" put ticket.txt && "$JABC" post 'c3' ) >/dev/null 2>&1 \
    || _fail "could not commit c3"
C3=$(wtlog_tip "$SRC/.be")
[ -n "$C3" ] || _fail "no c3 sha"
C3LET=$(printf '%s' "$C3" | cut -c1-8)

# --- 1) scoped pick, base stays put: the report shows the divergence -------
cp "$DEST/.be" "$WORK/dest.be.before"
RC=0
( cd "$DEST" && "$JABC" get "//srcwt/ticket.txt" ) \
    >"$WORK/pick.out" 2>"$WORK/pick.err" || RC=$?
[ "$RC" = 0 ] || { cat "$WORK/pick.err" >&2; _fail "get //srcwt/ticket.txt exit=$RC"; }
[ "$(cat "$DEST/ticket.txt")" = "ticket work v2" ] || _fail "pick did not land v2"
cmp -s "$DEST/.be" "$WORK/dest.be.before" || _fail "a pick moved dest's wtlog"
grep -qF "o... ?$C3LET" "$WORK/pick.out" \
    || { cat "$WORK/pick.out"; _fail "no 'o... ?$C3LET' commit row (track ahead of base)"; }
grep -qF "v..v ticket.txt" "$WORK/pick.out" \
    || { cat "$WORK/pick.out"; _fail "no 'v..v ticket.txt' file row (picked bytes as dirt)"; }

# --- 2) bare sync to the track: base catches up, the report goes silent ----
RC=0
( cd "$DEST" && "$JABC" get ) >"$WORK/sync.out" 2>"$WORK/sync.err" || RC=$?
[ "$RC" = 0 ] || { cat "$WORK/sync.err" >&2; _fail "bare get exit=$RC"; }
od -An -c "$DEST/.be" | tr -d ' \n' | grep -q "//srcwt#$C3" \
    || _fail "dest does not track //srcwt#$C3"
if grep -qF "o... ?" "$WORK/sync.out"; then
    cat "$WORK/sync.out"; _fail "a synced wt still reports an 'o...' commit row"
fi
if grep -qF "v..v" "$WORK/sync.out"; then
    cat "$WORK/sync.out"; _fail "a synced wt still reports an advanced file row"
fi

echo "PASS [$NAME]"
