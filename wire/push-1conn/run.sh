#!/bin/sh
#  wire/push-1conn — GIT-019: ONE receive-pack session per FF push.  Same FF
#  push as push-ssh, but assert (1) NO `remote end hung up unexpectedly` on
#  stderr (the advert-only session used to close without a flush-pkt) and (2)
#  ssh (→ git-receive-pack) is spawned EXACTLY ONCE (advert #1 + advert #2 were
#  two connections).  A counting ssh shim tallies each spawn.  Needs
#  ssh-to-localhost (WITH_SSH); SKIPs cleanly otherwise.
. "$(dirname "$0")/../lib/wirecase.sh"

wire_push_seed
cur=$(wire_local_commit "$PWT" "$(printf 'A\nB\n')")
[ -n "$cur" ] && [ "$cur" != "$PA" ] || _fail "local commit did not advance cur"

#  GIT-019: a counting ssh shim — each real receive-pack connection ticks the
#  tally file, then execs the real ssh.  wire.classify honours $SSH_BIN.
SSHREAL=$(command -v ssh)
SHIM="$WORK/ssh-shim"; TALLY="$WORK/ssh.count"; : > "$TALLY"
cat > "$SHIM" <<SHEOF
#!/bin/sh
printf 'x' >> "$TALLY"
exec "$SSHREAL" "\$@"
SHEOF
chmod +x "$SHIM"

( cd "$PWT" && SSH_BIN="$SHIM" "$JABC" post "ssh://localhost/$PREL?master" ) \
  >"$WORK/push.out" 2>"$WORK/push.err" \
  || { echo "--- err ---"; cat "$WORK/push.err"; _fail "ssh FF push failed"; }

#  Primary observable: the gratuitous hangup line is GONE.
if grep -qi 'hung up' "$WORK/push.err"; then
  echo "--- err ---"; cat "$WORK/push.err"
  _fail "FF push still prints 'the remote end hung up unexpectedly'"
fi

#  One receive-pack session: the shim was invoked exactly once.
n=$(wc -c < "$TALLY" | tr -d ' ')
[ "$n" = "1" ] || _fail "expected 1 receive-pack ssh spawn, got $n"

after=$(git -C "$PBARE" rev-parse master)
[ "$after" = "$cur" ] || _fail "bare master did not FF-advance to cur ($cur; got $after)"
git -C "$PBARE" fsck >/dev/null 2>&1 || _fail "pushed bare fails fsck"
pass
