#!/bin/sh
# test/todo/rowcache — TODO-006 r3: the board row's per-block STRUCTURED cache
# in the pager (the ticket HEADS, the wt FILE counts, the ahbeh pair), each
# dropped by its OWN witness — the [STATUS-019] rev tree for the two dirs, a
# `tips` fingerprint for the refs no fs event can witness.  The row itself is
# rendered from those numbers EVERY time, through the one titleRow.
# A resident process (drive.js, the pager's driveSpell shape) runs the REAL
# `todo` verb over a REAL board: a project wt owning todo/TIC + todo/BUG and
# three work/ worktrees cloned off its own store.  The assertions are
# implementation-blind — the CFOLD-001 JAB_STATS object-read counter, a count of
# every io.open/io.readdir under the ticket tree, which worktrees classifyMerge
# ran for, and the emitted hunk BYTES:
#   * a re-render with nothing changed is byte-identical, reads ~0 objects,
#     classifies nothing and touches the ticket tree ZERO times;
#   * a write under ONE wt re-classifies THAT wt only;
#   * one ticket edit re-reads THAT topic's heads, not the other topic's;
#   * a POST to the tracked upstream — no fs event under the wts at all —
#     refreshes the AHBEH numbers only: file frames byte-identical, no classify;
#   * the pty leg runs gritzko's field gesture: click a ticket, BACKSPACE back,
#     and that FIRST re-fire must hit.
# RED before TODO-006: no cache, so every re-fire pays the full per-wt work; and
# before the r3 fix the watcher started only AFTER the cold render, so the first
# re-fire always missed wholesale.
# Registered by the be/test glob as be-js-todo-rowcache.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/todo/rowcache
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "todo/rowcache: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "todo/rowcache: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

# The memo exists only under a LIVE watcher; a jab without the JAB-032 fsw wd
# API cannot start one, so skip rather than fail.
"$BE" --eval 'let w=fsw.init(); let d=fsw.dir(w,"/tmp"); fsw.close(w); if(!(d>0)) throw "old";' \
    >/dev/null 2>&1 || { echo "todo/rowcache: SKIP — jab has no fsw wd API (JAB-032)" >&2; exit 0; }

: "${TMP:=/tmp}"; export TMP
WORK="$TMP/$$/todo/rowcache"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the jsrc symlink (barewords resolve via jab's upward scan).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [todo/rowcache] $*" >&2; exit 1; }

# --- the PROJECT ROOT: its `.be/` anchor is what projectRoot() climbs to -----
# URI-016: todoRoot() = <project root>/todo, workRoot() = <project root>/work.
# Several files over several commits, so a MISS reads a meaningful number of
# objects and the `~0 on a hit` bar means something.
WT="$WORK/wt"; mkdir -p "$WT/.be/" "$WT/src"
for i in 1 2 3 4 5 6; do printf 'seed %s\n' "$i" > "$WT/src/f$i.txt"; done
printf 'seed\n' > "$WT/a.txt"
( cd "$WT" && "$BE" post 'c0' ) >/dev/null 2>&1 || _fail "seed project"
for c in 1 2 3; do
    printf 'rev %s\n' "$c" > "$WT/src/f$c.txt"
    ( cd "$WT" && "$BE" put "src/f$c.txt" && "$BE" post "c$c" ) >/dev/null 2>&1 \
        || _fail "seed commit c$c"
done
( cd "$WT" && "$BE" put '?trunk' ) >/dev/null 2>&1 || _fail "name the trunk"

# --- the work/ worktrees: real clones of the project's OWN store, ?trunk-------
# TIC-002 gets a LOCAL commit at fixture time, so the driver can PUSH it from
# another process later: that rewrites the shared `<shard>/refs` tip TIC-001's
# ahbeh column reads while touching NO file under TIC-001.
mkdir -p "$WT/work"
_clone() {
    mkdir -p "$WT/work/$1"
    rm -f "$WT"/.be/*/*.keeper.idx 2>/dev/null || true
    ( cd "$WT/work/$1" && "$BE" get "file://$WT/.be?trunk" ) >/dev/null 2>&1 \
        || _fail "clone work/$1"
}
_clone TIC-001
_clone TIC-002
_clone BUG-001
printf 'two\n' > "$WT/work/TIC-002/M.txt"
( cd "$WT/work/TIC-002" && "$BE" put M.txt && "$BE" post 'c1' ) >/dev/null 2>&1 \
    || _fail "TIC-002 local commit"

# --- the ticket board (planted AFTER the seed commit: pure fs, untracked) ----
mkdir -p "$WT/todo/TIC" "$WT/todo/BUG"
_tic() { printf '#   %s: %s\nNow: OPEN\nSev: MED\n\nbody\n' "$1" "$2" > "$WT/todo/$3/$1.mkd"; }
_tic TIC-001 'the first ticket, owns a worktree' TIC
_tic TIC-002 'the second ticket, owns a worktree' TIC
_tic TIC-003 'no worktree at all' TIC
_tic BUG-001 'a bug that owns a worktree' BUG
printf '#   BUG-002: a bug with no wt but a Rep:\nNow: OPEN\nRep: ///be\n\nbody\n' \
    > "$WT/todo/BUG/BUG-002.mkd"
# The plant must land on ONE mtime: metaidx re-lexes files with mtime >=
# max-seen, so a tick straddling these writes makes render 2 lex fewer files.
find "$WT/todo" -exec touch -r "$WT/todo/TIC/TIC-001.mkd" {} +

# JAB_STATS=1 turns on the CFOLD-001 object-read counters the driver reads.
JAB_STATS=1 "$BE" "$_CASE/drive.js" "$WT" "$TMP/$$/jsrc" "$BE" \
    > "$WORK/out" 2>"$WORK/err" || { cat "$WORK/out" "$WORK/err" >&2
                                     _fail "driver refused"; }
# io.log writes to fd 2 — the driver's leg report lands in err, not out.
grep -q '^PASS$' "$WORK/err" || { cat "$WORK/out" "$WORK/err" >&2; _fail "legs failed"; }
grep -E '^(ok |FAIL |cost: |PASS)' "$WORK/err" | sed 's/^/  /' || true

# --- the REAL UI path: a live pager board, re-fired and CLICKED --------------
# Runs on the same fixture, after the driver (which left work/TIC-001 dirty and
# the trunk moved — the pty leg only needs a working board).
if command -v python3 >/dev/null 2>&1 && python3 -c "import pty,select" 2>/dev/null; then
    python3 "$_CASE/board.py" "$BE" "$WT" > "$WORK/pty.log" 2>&1 || {
        cat "$WORK/pty.log" >&2; _fail "pty session"; }
    grep -q '^FAIL' "$WORK/pty.log" && { cat "$WORK/pty.log" >&2; _fail "pty legs"; }
    sed 's/^/  /' "$WORK/pty.log"
else
    echo "  todo/rowcache: pty leg SKIPPED — no python3 / pty module" >&2
fi
echo "PASS [todo/rowcache]"
