#!/bin/sh
# test/get/stamp — GET-049: every file get WRITES carries the get row's ts as
# its mtime (the STATUS-011 stamp-set invariant), so a fresh clone / update
# reads status-clean with ZERO per-file content reads.  Clone leg: all tracked
# files stamped to the clone row ts.  Update leg: only the written files
# restamp to the new row ts; untouched files keep the clone stamp intact; the
# delete needs no stamp.  assert.js carries the mtime + io.open-count checks.
. "$(dirname "$0")/../../lib/getcase.sh"

SRC="$WORK/src"
mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt; printf 'B\n' > b.txt; printf 'M\n' > m.txt
mkdir d; printf 'C\n' > d/c.txt
"$BE" post 'c1' >/dev/null 2>&1
"$BE" post '?' >/dev/null 2>&1

DST="$WORK/wt"; mkdir "$DST"
( cd "$DST" && "$JABC" get "file:$SRC/.be" ) >/dev/null 2>&1 || _fail "clone failed"
"$JABC" "$_CASE/assert.js" "$DST" clone || _fail "clone: unstamped files / content reads"

# update: mod b.txt, add z.txt, delete m.txt; a.txt + d/c.txt untouched.
cd "$SRC"
printf 'B2\n' > b.txt; printf 'Z\n' > z.txt
"$BE" put b.txt z.txt >/dev/null 2>&1
"$BE" delete m.txt >/dev/null 2>&1
"$BE" post 'c2' >/dev/null 2>&1
"$BE" post '?' >/dev/null 2>&1

( cd "$DST" && "$JABC" get "file:$SRC/.be" ) >/dev/null 2>&1 || _fail "update failed"
"$JABC" "$_CASE/assert.js" "$DST" update b.txt z.txt -- a.txt d/c.txt \
    || _fail "update: written files unstamped or untouched mtimes churned"

pass
