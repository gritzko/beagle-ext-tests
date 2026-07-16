#!/bin/sh
# test/get/be-update — GET-046: the UPDATE fetch over a LOCAL keeper store
# (`be:/abs/path/.be`, host-less → local `keeper upload-pack` exec — no ssh),
# pinning the second-leg failure of test/get/be: keeper serves its multi-pack
# store log VERBATIM (the first embedded pack's header + every appended record
# behind it), so the pack header UNDERCOUNTS and a scan-only ingest index
# misses the tail objects — `jab get` then dies with "tip <sha> has no tree"
# on the update leg while the fresh clone passes.  Asserts clone + update
# stdout/worktree/status against the committed golden.
. "$(dirname "$0")/../../lib/getcase.sh"

# Local keeper exec: getcase pins KEEPER_BIN=$BIN/keeper; fall back to PATH,
# SKIP (never false-FAIL) when no keeper binary is reachable at all.
if [ ! -x "$KEEPER_BIN" ]; then
    KEEPER_BIN=$(command -v keeper 2>/dev/null || true)
    [ -n "$KEEPER_BIN" ] && [ -x "$KEEPER_BIN" ] || { echo "SKIP [be-update] no keeper"; exit 0; }
    export KEEPER_BIN
fi

SRC="$WORK/src"
mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt; printf 'B\n' > b.txt; printf 'M\n' > m.txt
mkdir d; printf 'C\n' > d/c.txt
"$BE" post 'c1' >/dev/null 2>&1
"$BE" post '?' >/dev/null 2>&1

REMOTE="be:$SRC/.be"
mkdir "$WORK/nT" "$WORK/jT"

get_both "$REMOTE" "$WORK/nT" "$WORK/jT"
status_both "$WORK/nT" "$WORK/jT"

# The update: mod / new / del — the source store log gains an APPENDED pack
# (post lands the new objects behind the clone pack), the exact shape the
# keeper wire re-serves with the stale first-pack header count.
cd "$SRC"
printf 'M2\n' > m.txt; printf 'Z\n' > z.txt
mkdir g; printf 'G\n' > g/g.txt
rm b.txt; rm -r d
"$BE" put m.txt z.txt g/g.txt >/dev/null 2>&1
"$BE" delete b.txt >/dev/null 2>&1
"$BE" delete d/c.txt >/dev/null 2>&1
"$BE" post 'multi' >/dev/null 2>&1
"$BE" post '?' >/dev/null 2>&1

get_both "$REMOTE" "$WORK/nT" "$WORK/jT"
status_both "$WORK/nT" "$WORK/jT"

pass
