#!/bin/sh
#  GIT-016 wire/head-ssh — `jab head ssh://peer?branch` (T4 FETCH peek).  Peer is
#  AHEAD of local; head must (a) report the behind `miss` commit, (b) NOT write a
#  packlog (.keeper count unchanged — the no-persist invariant), (c) advance the
#  remote-tracking ref to the peer tip, (d) leave the bare peer untouched.  ssh.
. "$(dirname "$0")/../lib/wirecase.sh"

wire_push_seed                                  # PBARE@A + a be worktree clone PWT@A
KBEFORE=$(find "$PWT/.be" -name '*.keeper' | wc -l | tr -d ' ')
[ "$KBEFORE" -ge 1 ] || _fail "clone left no keeper packlog"
REFS=$(find "$PWT/.be" -name refs | head -1)
[ -n "$REFS" ] || _fail "clone left no refs ULOG"

#  Advance the PEER ahead of local (a server commit B on top of A); local cur
#  stays at A, so the peer is AHEAD → head reports a behind `miss` commit.
B=$(wire_peer_advance "$PBARE")
[ "$B" != "$PA" ] || _fail "peer did not advance ahead of local"

#  Pre-head: the remote-tracking ULOG holds the clone tip A, NOT yet the peer B.
strings "$REFS" | grep -q "$B" && _fail "refs already carried peer tip B before head"

if ! ( cd "$PWT" && "$JABC" head "ssh://localhost/$PREL?master" ) \
       >"$WORK/head.out" 2>"$WORK/head.err"; then
  echo "--- err ---"; cat "$WORK/head.err"; _fail "head ssh exited non-zero"
fi

#  (a) the behind (miss) commit B is reported — its short hashlet appears, tagged
#  as a `miss` (behind) row.
b8=$(printf '%s' "$B" | cut -c1-8)
grep -q "$b8" "$WORK/head.out" \
  || { echo "--- out ---"; cat "$WORK/head.out"; _fail "behind commit $b8 not reported"; }
grep -qw miss "$WORK/head.out" \
  || { echo "--- out ---"; cat "$WORK/head.out"; _fail "no behind 'miss' row reported"; }

#  (b) no-persist: the local shard's .keeper packlog COUNT is unchanged.
KAFTER=$(find "$PWT/.be" -name '*.keeper' | wc -l | tr -d ' ')
[ "$KAFTER" = "$KBEFORE" ] \
  || _fail "head wrote a packlog (.keeper $KBEFORE -> $KAFTER) — no-persist broken"

#  (c) the remote-tracking ref advanced to the peer tip B (a new refs ULOG row).
strings "$REFS" | grep -q "$B" \
  || _fail "remote-tracking ref did not advance to the peer tip B"

#  (d) the bare peer is untouched by a read-only head.
peer_after=$(git -C "$PBARE" rev-parse master)
[ "$peer_after" = "$B" ] || _fail "head moved the bare peer ($B -> $peer_after)"
git -C "$PBARE" fsck >/dev/null 2>&1 || _fail "bare fails fsck"
pass
