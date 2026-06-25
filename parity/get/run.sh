#!/bin/sh
# JSQUE-009 parity case: `be get <file://remote>` via the resident loop — full
# -line byte parity, native `be get` vs `jab be/loop.js get` (SUT=loop).  GET is
# the big verb: the SEED resolves the remote once, anchors the wtlog, then FANS
# OUT a per-dir Merkle-pruned reconcile — per-file write/merge leaves + per-path
# delete leaves + recursive subdir rows, with a del-sweep barrier fold.  This
# case gates that the loop's get banner + the dir fan-out rows + the two
# worktrees are byte/file identical to native, over a file:// store-backed clone
# (covers a flat clone, a nested-dir fan-out, and a multi-verb update re-get).
#
# Default $SUT=oneshot is dead for get post-conversion (get.js is now a handler,
# no main() — the JSQUE-008 status precedent); `SUT=loop` gates the converted
# handler.  Models parity/get-dir (clone_parity over a fork pair) + the be-js-get
# getcase shape.
. "$(dirname "$0")/../../lib/parity.sh"

SRC="$WORK/src"
mkdir -p "$SRC"; cd "$SRC"; mkdir .be
# A flat file set + nested dirs (the fan-out): top files, a subdir, a deep dir.
printf 'A\n' > a.txt; printf 'B\n' > b.txt; printf 'M\n' > m.txt
mkdir d; printf 'C\n' > d/c.txt
mkdir d/e; printf 'E\n' > d/e/e.txt
"$BE" post 'c1' >/dev/null 2>&1

REMOTE="file://$SRC/.be?/src"
mkdir "$WORK/nT" "$WORK/jT"

# 1. fresh clone — the dir fan-out: every leaf is a `new` row (files + nested
#    dirs), the Merkle reconcile walks from the empty baseline.
clone_parity get "$REMOTE" "$WORK/nT" "$WORK/jT"

# 2. advance the source: mod m.txt, new z.txt + a new dir g/, del b.txt + the
#    deep dir d/e — the update fan-out (Merkle-prune of unchanged d/c.txt,
#    write/upd of m.txt, delete leaves for b.txt + d/e/e.txt).
cd "$SRC"
printf 'M2\n' > m.txt; printf 'Z\n' > z.txt
mkdir g; printf 'G\n' > g/g.txt
rm b.txt; rm -r d/e
"$BE" put m.txt z.txt g/g.txt >/dev/null 2>&1
"$BE" delete b.txt >/dev/null 2>&1
"$BE" delete d/e/e.txt >/dev/null 2>&1
"$BE" post 'multi' >/dev/null 2>&1

# 3. update re-get — the update fan-out (post banner + new/upd/del rows, the
#    Merkle prune keeping a.txt/d/c.txt untouched).
clone_parity get "$REMOTE" "$WORK/nT" "$WORK/jT"

# 4. GETOVRL refusal (JSQUE-014): advance the source with a NEW un-baselined
#    path (w.txt), then dirty that same path on disk in BOTH clones BEFORE the
#    re-get.  A dirty wt file overlaying a new target with no baseline to merge
#    refuses SNIFFOVRL/GETOVRL — and native refuses BEFORE the banner, so stdout
#    must be EMPTY on both sides (byte-parity) AND both exit NON-ZERO.  Confirms
#    the get.js overlap check moved ahead of any out.* push (loop-edge flush).
cd "$SRC"
printf 'Wsrc\n' > w.txt; "$BE" put w.txt >/dev/null 2>&1; "$BE" post 'ovrl' >/dev/null 2>&1
printf 'Wdirty\n' > "$WORK/nT/w.txt"
printf 'Wdirty\n' > "$WORK/jT/w.txt"
( cd "$WORK/nT" && run_native get "$REMOTE" ) >"$WORK/nT.out" 2>"$WORK/nT.err" && \
    _fail "native dirty-overlay get did not refuse (zero exit)"
( cd "$WORK/jT" && run_js     get "$REMOTE" ) >"$WORK/jT.out" 2>"$WORK/jT.err" && \
    _fail "JS dirty-overlay get did not refuse (zero exit)"
assert_stdout "$WORK/nT.out" "$WORK/jT.out"
grep -q GETOVRL "$WORK/jT.err" || _fail "JS dirty-overlay get refused but not via GETOVRL: $(cat "$WORK/jT.err")"
echo "ok: dirty-overlay GETOVRL no-banner + non-zero exit parity passes"

pass
