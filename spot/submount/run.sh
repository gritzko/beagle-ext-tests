#!/bin/sh
# test/js/spot/submount — JAB-026: the spot/grep/regex search VIEWs RECURSE into
# mounted submodules via the loop JOB QUEUE (enqueue one child row per sub), so
# their hunk stream matches native `be <scheme>:<uri> --plain` — each sub's hits
# carry the sub path prefix (`chsub/s.c#Lnn`).  The recursion crosses the store
# boundary: the handler re-discovers the sub's `.be` shard via be.find (NO fork,
# NO /proc), then searches it like the top repo (core/recurse.js enumerates the
# mounts; the loop FIFO drives the cross-store BFS — the ls:/lsr: pattern).
#
# Fixture mirrors test/js/ls/submount: a git sub `ch` (with a matching `.c`) is
# `submodule add`ed into `par`, then `be get be:par` clones + MOUNTS it into a
# beagle store.  Unlike ls/submount (a property check — native lsr: does NOT
# descend), search recursion IS byte-parity with native, so we diff against the
# native oracle via spot_eq.  Needs git + a be that git-imports; SKIPs otherwise.
. "$(dirname "$0")/../lib/spotcase.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git not found" >&2; exit 0; }
export GIT_CONFIG_GLOBAL=/dev/null

S="$WORK/git"; rm -rf "$S"; mkdir -p "$S"; cd "$S"
mkg() {
    git init -q -b master "$1" >/dev/null 2>&1 || return 1
    git -C "$1" config user.email t@t
    git -C "$1" config user.name  T
    git -C "$1" config protocol.file.allow always
}
mkg ch  || { echo "FAIL(setup): git init ch"  >&2; exit 1; }
# Sub matching .c near file top (window starts at line 1 -> no #func segment).
printf 'int sub_emit(int a) { return a; }\n' > ch/s.c
printf 'note text emit here\n'               > ch/n.txt
git -C ch add -A; git -C ch commit -qm c1
mkg par || { echo "FAIL(setup): git init par" >&2; exit 1; }
printf 'int par_emit(int b) { return b; }\n' > par/p.c
git -C par -c protocol.file.allow=always submodule add -q "$S/ch" chsub >/dev/null 2>&1 \
    || { echo "SKIP: submodule add unsupported" >&2; exit 0; }
git -C par add -A; git -C par commit -qm p1

mkdir -p "$S/B1/.be"
( cd "$S/B1" && "$BE" get "be:$S/par" >/dev/null 2>&1 ) || true
# Probe the mount: a be without git-import leaves no secondary-wt anchor — SKIP.
[ -f "$S/B1/chsub/.be" ] || { echo "SKIP: be did not mount the submodule" >&2; exit 0; }
cd "$S/B1"

# --- grep: parent hit + sub-prefixed sub hit, byte-parity with native --------
spot_eq "grep recurses into submodule"  'grep:.c#emit'
# --- regex: same recursion through the regex mode -----------------------------
spot_eq "regex recurses into submodule" 'regex:.c#emit'
# --- spot: structural mode recurses too (placeholder N binds the arg token) ---
spot_eq "spot recurses into submodule"  'spot:.c#int N'

pass
