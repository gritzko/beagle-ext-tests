#!/bin/sh
# test/todo/igload — BE-064: the board reads `.gitignore`/`.gitmodules` TWICE.
# The rev tree's `arm()` loads a wt's ignore matcher, walks the wt with it and
# publishes the walk (TODO-006) — then classifyMerge re-loaded that same matcher
# and re-parsed that same `.gitmodules` for the same root microseconds later, and
# recurse.walk parsed it a third time.  Nothing is CACHED here: the arming walk
# HANDS ITS WORK DOWN to the compute that follows the query.
# The fixture is the rowcache one, lean: a project wt owning todo/TIC + todo/BUG
# and two work/ worktrees cloned off its own store.  The driver (drive.js, the
# pager's driveSpell shape) runs the REAL `todo` verb in-process and counts, PER
# ARGUMENT, how often `ignore.load` and `gitmodules.paths` ran in ONE render —
# implementation-blind: a root read twice IS the duplicate leg.
#   * with a LIVE watcher no root is read twice (RED before BE-064: 2x per wt);
#   * those bytes equal the watcher-OFF render's bytes exactly (the gate: a
#     changed count is the goal, a changed byte is a bug);
#   * with the watcher stopped the counts are exactly the pre-watcher ones —
#     a mutation verb never starts one (loop.js), so its path must not move.
# Registered by the be/test glob as be-js-todo-igload.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/todo/igload
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "todo/igload: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "todo/igload: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

# The arming walk exists only under a LIVE watcher; a jab without the JAB-032
# fsw wd API cannot start one, so skip rather than fail.
"$BE" --eval 'let w=fsw.init(); let d=fsw.dir(w,"/tmp"); fsw.close(w); if(!(d>0)) throw "old";' \
    >/dev/null 2>&1 || { echo "todo/igload: SKIP — jab has no fsw wd API (JAB-032)" >&2; exit 0; }

: "${TMP:=/tmp}"; export TMP
WORK="$TMP/$$/todo/igload"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the jsrc symlink (barewords resolve via jab's upward scan).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [todo/igload] $*" >&2; exit 1; }

# --- the PROJECT ROOT: its `.be/` anchor is what projectRoot() climbs to -----
WT="$WORK/wt"; mkdir -p "$WT/.be/" "$WT/src"
for i in 1 2 3; do printf 'seed %s\n' "$i" > "$WT/src/f$i.txt"; done
printf 'seed\n' > "$WT/a.txt"
( cd "$WT" && "$BE" post 'c0' ) >/dev/null 2>&1 || _fail "seed project"
printf 'rev 1\n' > "$WT/src/f1.txt"
( cd "$WT" && "$BE" put "src/f1.txt" && "$BE" post 'c1' ) >/dev/null 2>&1 || _fail "seed commit"
( cd "$WT" && "$BE" put '?trunk' ) >/dev/null 2>&1 || _fail "name the trunk"

# --- the work/ worktrees: real clones of the project's OWN store, ?trunk------
mkdir -p "$WT/work"
_clone() {
    mkdir -p "$WT/work/$1"
    rm -f "$WT"/.be/*.keeper.idx 2>/dev/null || true
    ( cd "$WT/work/$1" && "$BE" get "file://$WT/.be?trunk" ) >/dev/null 2>&1 \
        || _fail "clone work/$1"
}
_clone TIC-001
_clone BUG-001
# a dirty file in one wt, so its FILE counts are not all zero
printf 'edit\n' > "$WT/work/TIC-001/a.txt"

# --- the ticket board (planted AFTER the seed commit: pure fs, untracked) ----
mkdir -p "$WT/todo/TIC" "$WT/todo/BUG"
_tic() { printf '#   %s: %s\nNow: OPEN\nSev: MED\n\nbody\n' "$1" "$2" > "$WT/todo/$3/$1.mkd"; }
_tic TIC-001 'the first ticket, owns a worktree' TIC
_tic TIC-002 'no worktree at all' TIC
_tic BUG-001 'a bug that owns a worktree' BUG
find "$WT/todo" -exec touch -r "$WT/todo/TIC/TIC-001.mkd" {} +

"$BE" "$_CASE/drive.js" "$WT" "$TMP/$$/jsrc" \
    > "$WORK/out" 2>"$WORK/err" || { cat "$WORK/out" "$WORK/err" >&2
                                     _fail "driver refused"; }
# io.log writes to fd 2 — the driver's leg report lands in err, not out.
grep -q '^PASS$' "$WORK/err" || { cat "$WORK/out" "$WORK/err" >&2; _fail "legs failed"; }
grep -E '^(ok |FAIL |     |PASS)' "$WORK/err" | sed 's/^/  /' || true
echo "PASS [todo/igload]"
