#!/bin/sh
# DIS-053 refs-parity: the JS `refs` view must spell trunk as the BARE `?`
# sigil, byte-matching the C side (`be head`), NEVER a literal `?trunk`.
#
# Before the fix, views/refs/refs.js did `branch = cur.branch || "trunk"` and
# emitted `branch:   ?trunk` for a no-`?branch` (trunk) worktree; C `be head`
# prints the trunk label as the bare `?` (graf/LOG.c, DIS-053 C-side fix).  The
# two diverged.  refs is a JS-only view (no native `be refs`), so the C oracle
# for the trunk SPELLING is `be head`: both must say `?`, neither `?trunk`.
#
# Read-only (no store write past the seed), so it runs in-place in one fork.
# Sources the parity harness (binaries, hermetic `.be` firewall, run_js/native).
. "$(dirname "$0")/../../lib/parity.sh"

# A trunk worktree: one committed file, no `?branch` ever minted → cur on trunk.
seed_baseline 'printf "A\n" > a.txt'
fork_pair

# --- the JS side: `jab refs` trunk label ------------------------------
# refs writes its report via io.log → fd 2, so fold stderr into the capture
# (same as the parity row probes); then read the `branch:` line.
( cd "$JS" && run_js refs ) >"$JS.out" 2>&1 || true
_jsline=$(grep '^branch:' "$JS.out" || true)
[ -n "$_jsline" ] || { cat "$JS.out"; _fail "no 'branch:' line in jab refs output"; }

# REGRESSION GUARD: the literal `?trunk` must NEVER appear (the bug).
case "$_jsline" in
    *'?trunk'*) cat "$JS.out"; _fail "jab refs spells trunk as '?trunk' (DIS-053)";;
esac
# The trunk label must be exactly the bare `?` sigil.
_jsbr=$(printf '%s\n' "$_jsline" | sed -E 's/^branch:[[:space:]]*//')
[ "$_jsbr" = "?" ] || { cat "$JS.out"; _fail "jab refs trunk label is '$_jsbr', want bare '?'"; }
echo "ok: jab refs spells trunk as the bare '?' sigil"

# --- the C oracle: `be head` trunk label ------------------------------
# C prints `head: ?: N ahead, …` for a trunk worktree.  Confirm the oracle
# uses the SAME bare `?` (and never `?trunk`), so the JS now byte-matches it.
( cd "$NAT" && run_native head ) >"$NAT.out" 2>"$NAT.err" || true
case "$(cat "$NAT.out")" in
    *'?trunk'*) cat "$NAT.out"; _fail "C be head spells trunk as '?trunk' — oracle drift";;
esac
grep -q '^head: ?:' "$NAT.out" || { cat "$NAT.out"; _fail "C be head trunk label is not the bare '?'"; }
echo "ok: C be head spells trunk as the bare '?' sigil — JS matches C"

pass
