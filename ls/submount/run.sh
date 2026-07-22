#!/bin/sh
# test/js/ls/submount — JAB-018/019: a mounted SUBMODULE is its own hunk in
# `lsr:`, recursed through the WORK QUEUE across the store boundary — the
# handler re-discovers the sub's shard via be.find and classifies it
# IN-PROCESS (NO fork, the JAB-004 seam).  This DELIBERATELY DIVERGES from
# native (native ls: shows the gitlink as `mis <sub>` and native lsr: does NOT
# descend into subs); the per-submodule-hunk recursion is the queue design
# (gritzko 2026-06-24: "one submodule or one subdir is a hunk").  So the
# assertions are property checks, not a native-parity diff.
#
# Fixture mirrors test/js/diff/08-sub-pin-bump-gitlink: a git sub `ch` (with a
# nested dir `lib/`) is `submodule add`ed into `par`, then imported over the GIT
# WIRE (git-upload-pack) — NO keeper — which mounts it into a beagle store.
# TEST-003: needs git + ssh-to-localhost + scratch under $HOME; SKIPs otherwise.
. "$(dirname "$0")/../lib/lscase.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git not found" >&2; exit 0; }
# TEST-003: the git-wire ingest is HOME-relative over ssh-to-localhost.
# BE_TEST_NO_SSH=1 force-skips ssh cases (CI); see wire/lib/wirecase.sh.
[ -z "${BE_TEST_NO_SSH:-}" ] || { echo "SKIP: BE_TEST_NO_SSH (ssh-to-localhost disabled)" >&2; exit 0; }
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
printf 'v1\n' > ch/c.txt; mkdir ch/lib; printf 'L\n' > ch/lib/l.txt
git -C ch add -A; git -C ch commit -qm c1
mkg par || { echo "FAIL(setup): git init par" >&2; exit 1; }
printf 'par\n' > par/p.txt; mkdir par/d; printf 'X\n' > par/d/x.txt
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
rm -f "$PWD/.be/queue" 2>/dev/null || true

# --- ls: root shows the mounted submodule as a navigable `dir` row ---------
"$JABC" ls "ls:" > "$WORK/ls.out" 2>/dev/null
grep -q '^        dir chsub/$' "$WORK/ls.out" \
    || { echo "--- ls: ---"; cat -A "$WORK/ls.out"; _fail "ls: no 'dir chsub/' row"; }
echo "ok   ls: submodule shown as navigable dir row"

# --- lsr: recurses INTO the submodule as its OWN hunk(s), across the store
#     boundary — its files listed RELATIVE to the sub hunk (c.txt, lib/, …) ---
rm -f "$PWD/.be/queue" 2>/dev/null || true
"$JABC" lsr "lsr:" > "$WORK/lsr.out" 2>/dev/null
# URI-014: the per-dir banner is now the `word URI` spell (`lsr chsub/`), the
# verb OUT of the scheme — native still bakes `lsr:` (C follow-up).
for _need in '^lsr chsub/$' ' eq  c.txt$' '        dir lib/$' \
             '^lsr chsub/lib/$' ' eq  l.txt$'; do
    grep -q "$_need" "$WORK/lsr.out" \
        || { echo "--- lsr: ---"; cat -A "$WORK/lsr.out"; _fail "lsr: missing /$_need/"; }
done
echo "ok   lsr: submodule recursed as its own hunk(s) across the store boundary"

pass
