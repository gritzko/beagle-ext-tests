#!/bin/sh
#  test/patch/tree-uri — PATCH-010: `jab patch <tree-uri>` absorbs ANOTHER
#  WORKTREE of the SAME store: theirs = the addressed wt's cur tip (its own
#  wtlog cur row), fork = LCA — a WHOLE-style whole-stack absorb.  And a
#  scheme'd arg patch cannot serve refuses LOUDLY, never read as a cherry ref.
#
#       T0 ── T1          ← w1 (trunk): T1 edits line 1
#         \
#          F1             ← w2 (?feat): F1 edits line 3 (disjoint → clean merge)
#
#  Fixture: ONE origin store, TWO secondary worktrees cloned off it; w2 holds
#  the extra commit F1.  `jab patch file:../w2` from w1 must merge F1 in.
. "$(dirname "$0")/../../lib/patchcase.sh"

#  origin store: boot trunk T0, label the feat fork (no switch)
ORG="$WORK/org"; mkdir -p "$ORG/.be"
_opwd=$(pwd)
cd "$ORG"
printf 'a\nb\nc\nd\ne\n' > f.txt
_boot 't0'
_fork feat
cd "$_opwd"

#  two SECONDARY worktrees off the ONE origin store (TEST-003: drop the origin's
#  rolling keeper.idx before each op so every commit stays visible)
_org_jab() { _d=$1; shift; rm -f "$ORG"/.be/*.keeper.idx; ( cd "$_d" && "$BE" "$@" ); }
#  DIS-076: default clone = the WORKTREE, pinned at its OWN cur (no ref needed
#  — a bare post never mints one).
ORG_TIP=$(_orgtip "$ORG")
W1="$WORK/w1"; mkdir -p "$W1"
_org_jab "$W1" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 || _fail "w1 clone failed"
W2="$WORK/w2"; mkdir -p "$W2"
_org_jab "$W2" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 || _fail "w2 clone failed"

#  w2 → ?feat, ONE commit ahead: F1 edits line 3
_org_jab "$W2" get '?feat' >/dev/null 2>&1 || _fail "w2 get ?feat failed"
printf 'a\nb\nC\nd\ne\n' > "$W2/f.txt"
_org_jab "$W2" put f.txt >/dev/null 2>&1 || _fail "w2 put failed"
_org_jab "$W2" post 'f1 line3' >/dev/null 2>&1 || _fail "w2 post failed"

#  w1 stays on trunk and grows its own T1: edits line 1 (disjoint)
printf 'A\nb\nc\nd\ne\n' > "$W1/f.txt"
_org_jab "$W1" put f.txt >/dev/null 2>&1 || _fail "w1 put failed"
_org_jab "$W1" post 't1 line1' >/dev/null 2>&1 || _fail "w1 post failed"

#  THE REPRO: a relative `file:<path>` tree URI absorbs w2's cur tip into w1
rm -f "$ORG"/.be/*.keeper.idx
( cd "$W1" && "$JABC" patch 'file:../w2' ) >"$WORK/js.out" 2>"$WORK/js.err" \
    || _fail "tree-uri patch failed: $(cat "$WORK/js.err")"

#  refusals: a scheme patch cannot serve dies LOUDLY (one uniform line), never
#  misread as a cherry ref.  RE-RULED 2026-07-10 (PATCH-011): be:// rides the
#  WIRE fetch leg — a DEAD wire source refuses loudly (PATCHFETCH) BEFORE any
#  wt/store mutation; the host is pinned deterministically-dead (.invalid,
#  RFC 2606 — never a live network dependency; ssh noise precedes the JS line
#  on stderr, so the assert greps, mirroring fetch-cross-store's dead source).
! ( cd "$W1" && "$JABC" patch 'svn:trunk/x' ) >/dev/null 2>"$WORK/e1" \
    || _fail "bogus scheme did not refuse"
! ( cd "$W1" && "$JABC" patch 'be://dead.invalid/x/y' ) >/dev/null 2>"$WORK/e2" \
    || _fail "be:// dead wire source did not refuse"
! ( cd "$W1" && "$JABC" patch 'file:../w2?feat' ) >/dev/null 2>"$WORK/e3" \
    || _fail "file:+query (store form) did not refuse"

{
    echo "=== stdout ===";       cat "$WORK/js.out"
    echo "=== patch row ===";    _patch_row "$W1"
    echo "=== status ===";       _jstatus "$W1"
    echo "=== file bytes ===";   _fbytes "$W1" f.txt
    echo "=== refuse bogus scheme ===";  sed -n 1p "$WORK/e1"
    echo "=== refuse dead wire (be://) ==="
    if grep -q "PATCHFETCH" "$WORK/e2"; then echo "refused loudly"; else
        echo "NO loud refusal: $(head -1 "$WORK/e2")"; fi
    echo "rows=$(grep -ac $'\tpatch\t' "$W1/.be" || true)"
    _fbytes "$W1" f.txt
    echo "=== refuse file:+query ===";   sed -n 1p "$WORK/e3"
} | golden_assert "$NAME" "$GOLDEN"
pass
