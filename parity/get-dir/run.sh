#!/bin/sh
# JSQUE-007 parity case: `be get <remote>` dir fan-out — full-line byte
# parity, native vs the JS path.  A source repo with nested dirs is committed,
# then cloned by BOTH native `be get` and the JS path (per $SUT) into two
# fresh worktrees; clone_parity asserts the get banner + the per-leaf
# write/new rows (the dir fan-out) are byte-identical, and the two worktrees
# match file-for-file.  A second commit (mod + new + del across dirs) drives
# the update-get fan-out.  Flip `SUT=loop` to gate be/loop.js — no edit here.
. "$(dirname "$0")/../../lib/parity.sh"

SRC="$WORK/src"
mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt; printf 'B\n' > b.txt; printf 'M\n' > m.txt
mkdir d; printf 'C\n' > d/c.txt
mkdir d/e; printf 'E\n' > d/e/e.txt
"$BE" post 'c1' >/dev/null 2>&1

REMOTE="file://$SRC/.be?/src"
mkdir "$WORK/nT" "$WORK/jT"

# 1. fresh clone — dir fan-out of all leaves (files + nested dirs).
clone_parity get "$REMOTE" "$WORK/nT" "$WORK/jT"

# 2. advance source: mod m.txt, new z.txt + new dir g/, del b.txt + dir d/e.
cd "$SRC"
printf 'M2\n' > m.txt; printf 'Z\n' > z.txt
mkdir g; printf 'G\n' > g/g.txt
rm b.txt; rm -r d/e
"$BE" put m.txt z.txt g/g.txt >/dev/null 2>&1
"$BE" delete b.txt >/dev/null 2>&1
"$BE" delete d/e/e.txt >/dev/null 2>&1
"$BE" post 'multi' >/dev/null 2>&1

# 3. update re-get — the update fan-out (new/upd/del rows).
clone_parity get "$REMOTE" "$WORK/nT" "$WORK/jT"

pass
