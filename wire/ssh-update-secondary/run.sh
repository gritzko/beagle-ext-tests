#!/bin/sh
#  wire/ssh-update-secondary — GET-041: `jab get ssh://…` INSIDE a store-backed
#  (secondary) worktree, whose `.be` is a redirect FILE to the shared store, must
#  land the fetched pack in the EXISTING shard that anchor references — never
#  treat `<wt>/.be` as a green-field store dir (mkdir/open under the redirect
#  file ENOTDIR-crashed after the whole pack was fetched).  Clone A (primary),
#  mount B off A's store (file:), advance the bare, ssh-get INSIDE B: B moves to
#  the new tip, the pack lands in A's shard, A's own wt position is untouched.
. "$(dirname "$0")/../lib/wirecase.sh"

wire_seed
#  A: primary ssh clone (owns the store at jA/.be, shard `repo`).
mkdir "$WORK/jA"
( cd "$WORK/jA" && "$JABC" get "ssh://localhost/$REL" ) >"$WORK/jA.out" 2>"$WORK/jA.err" \
  || { cat "$WORK/jA.err"; _fail "ssh clone (primary) failed"; }
[ "$(wire_tip "$WORK/jA")" = "$TIP_V2" ] || _fail "primary clone tip != HEAD $TIP_V2"
#  JS-117: a clone mints exactly ONE keeper log (everything after tail-appends).
[ "$(ls "$WORK/jA/.be/repo/" | grep -c '\.keeper$')" -eq 1 ] \
  || _fail "clone minted != 1 keeper log"

#  B: a SECONDARY worktree off A's store — its `.be` is a redirect FILE.
mkdir "$WORK/jB"
( cd "$WORK/jB" && "$JABC" get "file:$WORK/jA/.be?/repo" ) >"$WORK/jB.out" 2>"$WORK/jB.err" \
  || { cat "$WORK/jB.err"; _fail "secondary file: mount failed"; }
[ -f "$WORK/jB/.be" ] || _fail "jB/.be is not a redirect FILE (not a secondary wt)"

#  Advance the bare: c3 on master.
printf 'D\n' > "$SEED/d3.txt"
git -C "$SEED" add -A; git -C "$SEED" commit -qm c3
git -C "$SEED" push -q "$BARE" master:master
TIP_V3=$(git -C "$BARE" rev-parse master)

#  The GET-041 repro: ssh-get INSIDE the secondary wt.
( cd "$WORK/jB" && "$JABC" get "ssh://localhost/$REL" ) >"$WORK/jB2.out" 2>"$WORK/jB2.err" \
  || { cat "$WORK/jB2.err"; _fail "ssh update inside a secondary wt crashed (GET-041)"; }
t=$(grep -aoE '#[0-9a-f]{40}' "$WORK/jB/.be" 2>/dev/null | tail -1 | tr -d '#')
[ "$t" = "$TIP_V3" ] || _fail "secondary tip $t != advanced HEAD $TIP_V3"
[ -f "$WORK/jB/d3.txt" ] || _fail "advanced file d3.txt missing in the secondary wt"
[ -f "$WORK/jB/.be" ] || _fail "jB/.be redirect FILE clobbered"
#  JS-117: the pack tail-APPENDED into A's shard log (d3.txt above proves the
#  landing) — the keeper-log count is UNCHANGED, nothing minted under jB.
n=$(ls "$WORK/jA/.be/repo/" | grep -c '\.keeper$')
[ "$n" -eq 1 ] || _fail "keeper log count changed across the update (n=$n)"
#  A's OWN wt position is untouched (B moved; A still at v2).
[ "$(wire_tip "$WORK/jA")" = "$TIP_V2" ] || _fail "primary wt tip moved by B's get"
pass
