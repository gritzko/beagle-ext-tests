#!/bin/sh
#  wire/push-nokeeper — GIT-018: `jab post` FF-pushes over ssh with NO keeper
#  binary reachable, proving buildPushPack builds the pack in PURE JS (no
#  `keeper upload-pack` spawn).  We point KEEPER_BIN at a non-existent path so
#  ANY local keeper spawn WOULD fail; the JS builder must still ship an accepted
#  pack.  Assert: the push succeeds (peer reports `unpack ok`), the bare's
#  master FF-advances to cur, and the pushed bare stays fsck-clean.  Adapts
#  push-ssh; needs ssh-to-localhost (WITH_SSH).
. "$(dirname "$0")/../lib/wirecase.sh"

#  The seed clone rides ssh to the REMOTE keeper (DOG_REMOTE_PATH) — unaffected;
#  only the LOCAL push-pack build must be keeper-free.  Break the local keeper.
KEEPER_BIN=/nonexistent/keeper-GIT018; export KEEPER_BIN

wire_push_seed
cur=$(wire_local_commit "$PWT" "$(printf 'A\nB\n')")
[ -n "$cur" ] && [ "$cur" != "$PA" ] || _fail "local commit did not advance cur"

#  Sanity: the broken KEEPER_BIN is genuinely unspawnable (a real keeper spawn
#  here would abort) — so a green push proves the JS builder, not a fallback.
[ ! -x "$KEEPER_BIN" ] || _fail "test bug: KEEPER_BIN unexpectedly executable"

( cd "$PWT" && "$JABC" post "ssh://localhost/$PREL?master" ) \
  >"$WORK/push.out" 2>"$WORK/push.err" \
  || { echo "--- err ---"; cat "$WORK/push.err"; _fail "no-keeper push failed"; }

after=$(git -C "$PBARE" rev-parse master)
[ "$after" = "$cur" ] || _fail "bare master did not FF-advance to cur ($cur; got $after)"
git -C "$PBARE" fsck --strict >"$WORK/fsck.out" 2>&1 || { cat "$WORK/fsck.out"; _fail "pushed bare fails fsck"; }
pass
