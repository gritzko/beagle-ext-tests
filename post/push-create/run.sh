#!/bin/sh
#  post/push-create — POST-027 cell 5-i: create-on-push.  `jab post
#  ssh://…?newbr` against a peer that does NOT have that branch: the advert
#  carries no old sha, relate's FF-from-nothing arm allows it, and pushRemote
#  (verbs/post/post.js:424-499) creates refs/heads/newbr at cur's tip over the
#  wire.  Spec: /wiki/POST.mkd §"Summary of invocation patterns" row 5 ("an
#  absent branch is created" is row 3's local rule, carried to the wire).
#  Asserts peer's newbr == cur, master untouched, bare fsck-clean.  Needs
#  ssh-to-localhost (WITH_SSH).
. "$(dirname "$0")/../../wire/lib/wirecase.sh"

wire_push_seed
cur=$(wire_local_commit "$PWT" "$(printf 'A\nNEW\n')")
[ -n "$cur" ] && [ "$cur" != "$PA" ] || _fail "local commit did not advance cur"
git -C "$PBARE" rev-parse -q --verify refs/heads/newbr >/dev/null 2>&1 \
  && _fail "peer already has newbr (bad fixture)"

( cd "$PWT" && "$JABC" post "ssh://localhost/$PREL?newbr" ) \
  >"$WORK/push.out" 2>"$WORK/push.err" \
  || { echo "--- err ---"; cat "$WORK/push.err"; _fail "create-on-push failed"; }

after=$(git -C "$PBARE" rev-parse -q --verify refs/heads/newbr 2>/dev/null || true)
[ "$after" = "$cur" ] || _fail "peer newbr not created at cur ($cur; got '$after')"
master=$(git -C "$PBARE" rev-parse master)
[ "$master" = "$PA" ] || _fail "create-on-push moved master ($PA -> $master)"
git -C "$PBARE" fsck >/dev/null 2>&1 || _fail "pushed bare fails fsck"
pass
