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
# nested dir `lib/`) is `submodule add`ed into `par`, then `be get be:par`
# clones + MOUNTS it into a beagle store.  Needs git + a be that git-imports;
# SKIPs cleanly otherwise.
. "$(dirname "$0")/../lib/lscase.sh"

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
printf 'v1\n' > ch/c.txt; mkdir ch/lib; printf 'L\n' > ch/lib/l.txt
git -C ch add -A; git -C ch commit -qm c1
mkg par || { echo "FAIL(setup): git init par" >&2; exit 1; }
printf 'par\n' > par/p.txt; mkdir par/d; printf 'X\n' > par/d/x.txt
git -C par -c protocol.file.allow=always submodule add -q "$S/ch" chsub >/dev/null 2>&1 \
    || { echo "SKIP: submodule add unsupported" >&2; exit 0; }
git -C par add -A; git -C par commit -qm p1

mkdir -p "$S/B1/.be"
( cd "$S/B1" && "$BE" get "be:$S/par" >/dev/null 2>&1 ) || true
# Probe the mount: a be without git-import leaves no secondary-wt anchor — SKIP.
[ -f "$S/B1/chsub/.be" ] || { echo "SKIP: be did not mount the submodule" >&2; exit 0; }
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
