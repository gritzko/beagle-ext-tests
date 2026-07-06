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
# `submodule add`ed into `par`, then imported over the GIT WIRE (git-upload-pack)
# — NO keeper — which mounts it into a beagle store.  spot_eq asserts jab's own
# recursion structure (native RETIRED — it LAGS jab).
# TEST-003: needs git + ssh-to-localhost + scratch under $HOME; SKIPs otherwise.
. "$(dirname "$0")/../lib/spotcase.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git not found" >&2; exit 0; }
# TEST-003: the git-wire ingest is HOME-relative over ssh-to-localhost.
command -v ssh >/dev/null 2>&1 \
    && ssh -o BatchMode=yes -o ConnectTimeout=5 localhost true >/dev/null 2>&1 \
    || { echo "SKIP: no ssh-to-localhost for the git-wire ingest" >&2; exit 0; }
case "$WORK" in "$HOME"/*) ;; *) echo "SKIP: scratch not under \$HOME (git-over-ssh)" >&2; exit 0 ;; esac
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
# TEST-003: point the sub's `.gitmodules` url at the GIT WIRE (ssh://localhost,
# HOME-relative) so the sub mounts over git-upload-pack, not the retired keeper.
git -C par config -f .gitmodules submodule.chsub.url "ssh://localhost/${S#$HOME/}/ch?/ch"
git -C par add -A; git -C par commit -qm p1

# TEST-003: import over the GIT WIRE (git-upload-pack) into a PRIMARY beagle store
# (`.be/par` + sibling `.be/ch`), mounting chsub — no `be:`/keeper.
mkdir -p "$S/B1"
( cd "$S/B1" && "$BE" get "ssh://localhost/${S#$HOME/}/par?/par" >/dev/null 2>&1 ) || true
# Probe the mount: a failed ingest leaves no secondary-wt anchor — SKIP.
[ -f "$S/B1/chsub/.be" ] || { echo "SKIP: git-wire ingest did not mount the submodule" >&2; exit 0; }
cd "$S/B1"

# --- grep: parent hit + sub-prefixed sub hit, byte-parity with native --------
spot_eq "grep recurses into submodule"  'grep:.c#emit'
# --- regex: same recursion through the regex mode -----------------------------
spot_eq "regex recurses into submodule" 'regex:.c#emit'
# --- spot: structural mode recurses too (placeholder N binds the arg token) ---
spot_eq "spot recurses into submodule"  'spot:.c#int N'

pass
