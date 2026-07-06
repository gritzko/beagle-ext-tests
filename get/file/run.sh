#!/bin/sh
# test/js/get/file — `bin/get.js` vs native `be get` over a file:// remote
# (a store-backed worktree).  Asserts byte-equivalent stdout + worktree +
# `be status` for: a fresh clone (new files+dirs) and a multi-verb update
# (mod / new / del, files AND dirs).
. "$(dirname "$0")/../../lib/getcase.sh"

SRC="$WORK/src"
mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt; printf 'B\n' > b.txt; printf 'M\n' > m.txt
mkdir d; printf 'C\n' > d/c.txt
# A fresh-repo `be post` commits the whole tree (no `be put` needed; `be put .`
# only re-stages tracked changes → PUTNONE on a fresh repo, fatal under set -e).
"$BE" post 'c1' >/dev/null 2>&1

# TEST-003: jab-seeded source is a single-shard UNNAMED-project colocated
# primary, so the clone URI carries NO `?/name` (named `?/x` misses jab's trunk).
REMOTE="file://$SRC/.be"
mkdir "$WORK/nT" "$WORK/jT"

# 1. fresh clone — all new (files + nested dirs).
get_both "$REMOTE" "$WORK/nT" "$WORK/jT"
status_both "$WORK/nT" "$WORK/jT"

# 2. advance the source: mod m.txt, new z.txt + new dir g/, del b.txt + dir d/.
cd "$SRC"
printf 'M2\n' > m.txt; printf 'Z\n' > z.txt
mkdir g; printf 'G\n' > g/g.txt
rm b.txt; rm -r d
"$BE" put m.txt z.txt g/g.txt >/dev/null 2>&1
"$BE" delete b.txt >/dev/null 2>&1
"$BE" delete d/c.txt >/dev/null 2>&1
"$BE" post 'multi' >/dev/null 2>&1

# 3. update re-get — post banner + new/upd/del rows.
get_both "$REMOTE" "$WORK/nT" "$WORK/jT"
status_both "$WORK/nT" "$WORK/jT"

pass
