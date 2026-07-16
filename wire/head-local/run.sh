#!/bin/sh
#  GIT-016 wire/head-local — local `jab head ?branch` (HEAD.mkd): cur vs a LOCAL
#  branch tip — ahead/behind counts PLUS the differing FILE paths, all objects
#  local, NO network, NO writes.  Two branches diverge by CONTENT off a shared
#  base A: cur (trunk) advances a.txt; `feat` adds b.txt.  head ?feat must report
#  the ahead `post` + behind `miss` commits AND the `chg a.txt`/`chg b.txt` paths.
#  ssh is used ONCE to bootstrap the be worktree (no native `be`) — SKIP otherwise.
. "$(dirname "$0")/../lib/wirecase.sh"

wire_push_seed                                  # PBARE@A + a be worktree clone PWT@A
cd "$PWT" || _fail "no PWT"

#  1) A `feat` branch off A: add b.txt, post it onto ?feat.
printf 'FEAT\n' > b.txt
"$JABC" put b.txt >/dev/null 2>&1 || _fail "put b.txt failed"
"$JABC" post '?feat' '#featmsg' >/dev/null 2>&1 || _fail "post ?feat failed"
# DIS-076: a message-post never mints/moves a ref — publish `?feat` explicitly
# so the later local `head '?feat'` peek (a refs-store read) can find it.
"$JABC" post '?feat' >/dev/null 2>&1 || _fail "publish ?feat failed"
# wt is attached to `feat` right now, so its own wtlog tip (wire_tip) IS it.
FEAT=$(wire_tip "$PWT")
[ -n "$FEAT" ] && [ "$FEAT" != "$PA" ] || _fail "feat did not advance off A"

#  2) Checkout back to A (drop the feat work from the wt), then advance the TRUNK
#  off A on a DIFFERENT file — the two tips now DIVERGE by content.
"$JABC" get "?#$PA" >/dev/null 2>&1 || _fail "checkout back to A failed"
rm -f b.txt
printf 'MASTER2\n' > a.txt
"$JABC" put a.txt >/dev/null 2>&1 || _fail "put a.txt failed"
"$JABC" post '?' '#trunkadv' >/dev/null 2>&1 || _fail "post trunk failed"

KBEFORE=$(find "$PWT/.be" -name '*.keeper' | wc -l | tr -d ' ')

#  3) The local peek: cur (diverged trunk) vs the local ?feat tip.
"$JABC" head '?feat' >"$WORK/hl.out" 2>"$WORK/hl.err" \
  || { cat "$WORK/hl.err"; _fail "head ?feat exited non-zero"; }

dump() { echo "--- out ---"; cat "$WORK/hl.out"; }

#  (a) ahead: cur's trunk-adv commit is reported as a `post` (local, would send).
grep -qw post "$WORK/hl.out" || { dump; _fail "no ahead 'post' row"; }
#  (b) behind: feat's commit is reported as a `miss` (behind), its hashlet shown.
f8=$(printf '%s' "$FEAT" | cut -c1-8)
grep -qw miss "$WORK/hl.out" || { dump; _fail "no behind 'miss' row"; }
grep -q "$f8" "$WORK/hl.out" || { dump; _fail "behind commit $f8 not reported"; }
#  (c) changed FILE paths: BOTH differing files appear as `chg` rows.
grep -qw chg "$WORK/hl.out" || { dump; _fail "no 'chg' changed-path row"; }
grep -qE 'chg[[:space:]]+a\.txt' "$WORK/hl.out" || { dump; _fail "a.txt not reported changed"; }
grep -qE 'chg[[:space:]]+b\.txt' "$WORK/hl.out" || { dump; _fail "b.txt not reported changed"; }

#  (d) purely local & write-free: no packlog written by the local peek.
KAFTER=$(find "$PWT/.be" -name '*.keeper' | wc -l | tr -d ' ')
[ "$KAFTER" = "$KBEFORE" ] \
  || _fail "local head wrote a packlog (.keeper $KBEFORE -> $KAFTER)"
pass
