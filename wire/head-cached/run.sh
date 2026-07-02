#!/bin/sh
#  GIT-016 wire/head-cached — `jab head //origin` CACHED read (T4), OFFLINE.  The
#  clone's remote-tracking tip == local cur, so the cached peek reports `eq` (the
#  get/eq column, nothing ahead/behind) with NO network and NO packlog written.
#  A `//host` authority (no scheme) is the cached form (store.eachRemote), so it
#  reads the reflog only — never the wire.  ssh only to build the clone.
. "$(dirname "$0")/../lib/wirecase.sh"

wire_push_seed                                  # PBARE@A + a be worktree clone PWT@A
KBEFORE=$(find "$PWT/.be" -name '*.keeper' | wc -l | tr -d ' ')
[ "$KBEFORE" -ge 1 ] || _fail "clone left no keeper packlog"

#  The cached authority matches the clone's remote-tracking row (origin trunk);
#  cur == that tip, so the OFFLINE peek is `eq`.
if ! ( cd "$PWT" && "$JABC" head "//localhost" ) \
       >"$WORK/hc.out" 2>"$WORK/hc.err"; then
  echo "--- err ---"; cat "$WORK/hc.err"; _fail "cached head exited non-zero"
fi

#  eq: the up-to-date column (relVerb maps eq -> `get`) carrying cur's hashlet,
#  and NOTHING ahead/behind (no `post`/`miss` rows).
cur8=$(printf '%s' "$PA" | cut -c1-8)
grep -q "$cur8" "$WORK/hc.out" \
  || { echo "--- out ---"; cat "$WORK/hc.out"; _fail "cached peek did not report cur's tip"; }
grep -qw get "$WORK/hc.out" \
  || { echo "--- out ---"; cat "$WORK/hc.out"; _fail "cached peek is not eq (no get/eq row)"; }
if grep -qwE 'miss|post' "$WORK/hc.out"; then
  echo "--- out ---"; cat "$WORK/hc.out"; _fail "eq peek wrongly reported ahead/behind rows"
fi

#  No packlog written (cached read is read-only; the no-persist invariant).
KAFTER=$(find "$PWT/.be" -name '*.keeper' | wc -l | tr -d ' ')
[ "$KAFTER" = "$KBEFORE" ] \
  || _fail "cached head wrote a packlog (.keeper $KBEFORE -> $KAFTER)"

#  Offline proof: the cached read reaches its verdict with the peer bare REMOVED
#  (no network / no store access) — a wire fetch would fail here; the reflog read
#  does not.  Re-run against the now-absent peer and still get eq.
rm -rf "$PBARE"
if ! ( cd "$PWT" && "$JABC" head "//localhost" ) \
       >"$WORK/hc2.out" 2>"$WORK/hc2.err"; then
  echo "--- err ---"; cat "$WORK/hc2.err"; _fail "cached head failed OFFLINE (peer removed)"
fi
grep -qw get "$WORK/hc2.out" \
  || { echo "--- out ---"; cat "$WORK/hc2.out"; _fail "offline cached peek not eq"; }
pass
