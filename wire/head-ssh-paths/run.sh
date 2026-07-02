#!/bin/sh
#  GIT-016 wire/head-ssh-paths — `jab head ssh://peer?branch` reports the changed
#  FILE paths too (the "+ changed paths" piece, HEAD.mkd).  Peer is AHEAD (a
#  server commit B edits a.txt); the REMOTE head fetch must list `chg a.txt` —
#  cur's tree vs the peer tip's tree, the tip tree read from a TRANSIENT in-memory
#  pack (NEVER persisted: the .keeper count stays put).  ssh; SKIP if unavailable.
. "$(dirname "$0")/../lib/wirecase.sh"

wire_push_seed                                  # PBARE@A + a be worktree clone PWT@A
KBEFORE=$(find "$PWT/.be" -name '*.keeper' | wc -l | tr -d ' ')

#  Advance the PEER ahead of local: wire_peer_advance edits a.txt (A -> A\nSERVER).
B=$(wire_peer_advance "$PBARE")
[ "$B" != "$PA" ] || _fail "peer did not advance ahead of local"

if ! ( cd "$PWT" && "$JABC" head "ssh://localhost/$PREL?master" ) \
       >"$WORK/hp.out" 2>"$WORK/hp.err"; then
  echo "--- err ---"; cat "$WORK/hp.err"; _fail "head ssh exited non-zero"
fi
dump() { echo "--- out ---"; cat "$WORK/hp.out"; }

#  (a) the behind commit B is reported (a `miss` row) — the graph core still holds.
b8=$(printf '%s' "$B" | cut -c1-8)
grep -q "$b8" "$WORK/hp.out" || { dump; _fail "behind commit $b8 not reported"; }
grep -qw miss "$WORK/hp.out" || { dump; _fail "no behind 'miss' row"; }

#  (b) the CHANGED PATH: a.txt (edited by the peer commit) is a `chg` row — the
#  remote head now reports differing paths, read from the transient fetched pack.
grep -qw chg "$WORK/hp.out" || { dump; _fail "no 'chg' changed-path row"; }
grep -qE 'chg[[:space:]]+a\.txt' "$WORK/hp.out" \
  || { dump; _fail "changed path a.txt not reported by remote head"; }

#  (c) no-persist: the changed-path tip tree came from the in-memory pack, so the
#  local shard's .keeper packlog COUNT is unchanged (transient, unpersisted).
KAFTER=$(find "$PWT/.be" -name '*.keeper' | wc -l | tr -d ' ')
[ "$KAFTER" = "$KBEFORE" ] \
  || _fail "head wrote a packlog (.keeper $KBEFORE -> $KAFTER) — no-persist broken"
pass
