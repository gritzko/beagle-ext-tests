#!/bin/sh
#  GIT-016 wire/head-bare — bare `jab head` ≡ the STATUS check (HEAD.mkd): cur vs
#  its parent/trunk, NO network, NO writes.  Assert the bare-head output EQUALS
#  the `jab status` view for the SAME repo state (head delegates to the status
#  view, not a reinvention).  Local only; ssh is used ONCE to bootstrap the be
#  worktree (the only non-native way to build a be store here) — SKIP otherwise.
. "$(dirname "$0")/../lib/wirecase.sh"

wire_push_seed                                  # PBARE@A + a be worktree clone PWT@A

#  A local commit so cur is AHEAD of the cached remote — a non-trivial status
#  (ahead 1) that both bare `head` and `status` must report identically.
B=$(wire_local_commit "$PWT" "LOCAL")
[ -n "$B" ] || _fail "local commit produced no tip"

#  Bare head vs status, same repo state, both offline & write-free.
( cd "$PWT" && "$JABC" head ) >"$WORK/head.out" 2>"$WORK/head.err" \
  || { cat "$WORK/head.err"; _fail "bare head exited non-zero"; }
( cd "$PWT" && "$JABC" status ) >"$WORK/status.out" 2>"$WORK/status.err" \
  || { cat "$WORK/status.err"; _fail "status exited non-zero"; }

#  (a) bare head == status, byte-for-byte (head IS the status view here).
if ! diff -u "$WORK/status.out" "$WORK/head.out" >"$WORK/diff.out" 2>&1; then
  echo "--- status ---"; cat "$WORK/status.out"
  echo "--- head ---";   cat "$WORK/head.out"
  echo "--- diff ---";   cat "$WORK/diff.out"
  _fail "bare head output differs from status"
fi
#  Non-empty guard: the status view actually produced a hunk (a `status` banner;
#  URI-014 dropped the scheme colon, so it is bare `status`, not `status:`).
grep -q "^status" "$WORK/head.out" \
  || { cat "$WORK/head.out"; _fail "bare head did not emit the status view"; }

#  (b) read-only: no packlog written by a bare head (it is the status check).
KB=$(find "$PWT/.be" -name '*.keeper' | wc -l | tr -d ' ')
( cd "$PWT" && "$JABC" head ) >/dev/null 2>&1
KA=$(find "$PWT/.be" -name '*.keeper' | wc -l | tr -d ' ')
[ "$KA" = "$KB" ] || _fail "bare head wrote a packlog (.keeper $KB -> $KA)"
pass
