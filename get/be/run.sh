#!/bin/sh
# test/js/get/be — `bin/get.js` vs native `be get` over a be:// remote
# (keeper-over-ssh: a REAL clone with its own object store + index).
# Asserts equivalent stdout + worktree + `be status` for a fresh clone
# (new files+dirs) and a multi-verb update (mod / new / del).
# Needs ssh-to-localhost (gated WITH_SSH in CMake).
. "$(dirname "$0")/../../lib/getcase.sh"

# HOME-relative path is what the ssh-side keeper resolves against.
REL=${SRC_REL:-}
SRC="$WORK/src"
mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt; printf 'B\n' > b.txt; printf 'M\n' > m.txt
mkdir d; printf 'C\n' > d/c.txt
# Fresh-repo `be post` commits the whole tree (`be put .` → PUTNONE here).
"$BE" post 'c1' >/dev/null 2>&1

# Derive the $HOME-relative path to the source .be for the ssh peer.
case "$SRC" in
    "$HOME"/*) RELBE="${SRC#$HOME/}/.be" ;;
    *) echo "SKIP [be] scratch not under \$HOME ($SRC)"; exit 0 ;;
esac
# TEST-003: the be:// transport spawns a `keeper upload-pack` peer over ssh; with
# no compatible keeper on PATH the be-store wire cannot serve — SKIP cleanly
# (server absent), never a false FAIL.  Also drop `?/src`: a jab-seeded source is
# a single-shard UNNAMED-project primary, so the clone URI carries no `?/name`.
command -v ssh >/dev/null 2>&1 || { echo "SKIP [be] no ssh"; exit 0; }
command -v keeper >/dev/null 2>&1 || { echo "SKIP [be] no keeper on PATH"; exit 0; }
REMOTE="be://localhost/$RELBE"
mkdir "$WORK/nT" "$WORK/jT"

get_both "$REMOTE" "$WORK/nT" "$WORK/jT"
status_both "$WORK/nT" "$WORK/jT"

cd "$SRC"
printf 'M2\n' > m.txt; printf 'Z\n' > z.txt
mkdir g; printf 'G\n' > g/g.txt
rm b.txt; rm -r d
"$BE" put m.txt z.txt g/g.txt >/dev/null 2>&1
"$BE" delete b.txt >/dev/null 2>&1
"$BE" delete d/c.txt >/dev/null 2>&1
"$BE" post 'multi' >/dev/null 2>&1

get_both "$REMOTE" "$WORK/nT" "$WORK/jT"
status_both "$WORK/nT" "$WORK/jT"

pass
