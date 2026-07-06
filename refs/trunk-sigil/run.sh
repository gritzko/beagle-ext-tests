#!/bin/sh
# DIS-053 refs-sigil: the JS `refs` view must spell trunk as the BARE `?`
# sigil, NEVER a literal `?trunk`.
#
# Before the fix, views/refs/refs.js did `branch = cur.branch || "trunk"` and
# emitted `branch:   ?trunk` for a no-`?branch` (trunk) worktree.
# TEST-003: native `be head` is RETIRED (it LAGS jab), so the trunk SPELLING is
# asserted INTRINSICALLY — jab refs must say the bare `?`, never `?trunk`.
#
# Read-only (no store write past the seed), so it runs in-place in one fork.
# Sources the (de-nativified) parity harness (binaries, `.be` firewall, run_js).
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
echo "ok: jab refs spells trunk as the bare '?' sigil (jab-intrinsic, no native oracle)"

pass
