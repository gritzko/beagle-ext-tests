#!/bin/sh
#  wire/put-dis011 — GIT-014/DIS-011: `jab put ssh://host/path` with NO ?ref is
#  LOG-ONLY — it records the URL in the wtlog and pushes NOTHING (no wire call,
#  no network).  Clone a local bare into a be worktree, run the log-only put with
#  an UNRESOLVABLE host, and assert: exit 0, NO network error, the URL is logged,
#  and the peer's master is UNCHANGED.  Needs ssh-to-localhost only to build the
#  be store (WITH_SSH).
. "$(dirname "$0")/../lib/wirecase.sh"

wire_push_seed
before=$(git -C "$PBARE" rev-parse master)

#  A bare `ssh://host/some/path` (no ?ref): log-only, must NOT touch the network.
( cd "$PWT" && "$JABC" put "ssh://host/some/path" ) \
  >"$WORK/put.out" 2>"$WORK/put.err" \
  || { echo "--- err ---"; cat "$WORK/put.err"; _fail "log-only put exited non-zero"; }

grep -qi "resolve hostname\|Broken pipe\|hung up" "$WORK/put.err" \
  && { echo "--- err ---"; cat "$WORK/put.err"; _fail "log-only put hit the network (must be log-only)"; }
grep -q "ssh://host/some/path" "$WORK/put.out" \
  || { echo "--- out ---"; cat "$WORK/put.out"; _fail "log-only put did not record the URL"; }
after=$(git -C "$PBARE" rev-parse master)
[ "$after" = "$before" ] || _fail "log-only put moved the remote ref ($before -> $after)"
pass
