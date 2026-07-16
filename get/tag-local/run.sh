#!/bin/sh
# test/get/tag-local — GET-047 / GET.mkd 1.2: `get ?<tag>` resolves a TAG from
# the LOCAL store, no wire leg (today only test/wire covers ?tags/v*).  jab has
# no dedicated tag verb: the local shape of a tag is a published `tags/<name>`
# ref row in the store's refs ULOG — `post '?tags/v1'` mints it at cur's tip,
# the same `tags/...` key the wire cases resolve.
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"
# DIS-076: publish the trunk explicitly so the switch-away leg has a ref.
cd "$SRC"
"$BE" post '?' >/dev/null 2>&1 || _fail "publish trunk failed"

gr_jclone "$SRC" "$WORK/jT"

# tag-worthy state: a commit onto ?feat, then `post '?tags/v1'` publishes the
# tag ref at cur's tip (created-at-tip, the FF-from-nothing advance).
cd "$WORK/jT"
printf 'V1\n' > f1.txt
"$JABC" put f1.txt >/dev/null 2>&1 || _fail "put f1.txt failed"
"$JABC" post '?feat' '#v1 work' >/dev/null 2>&1 || _fail "post ?feat failed"
"$JABC" post '?tags/v1' >/dev/null 2>&1 || _fail "publish ?tags/v1 failed"
VTIP=$(gr_tip_sha "$WORK/jT")
[ -n "$VTIP" ] && [ "$VTIP" != "$C1" ] || _fail "no distinct tagged tip"

# switch AWAY (trunk, c1) so the tag get observably moves the wt.
rc=$(gr_jget "$WORK/jT" '?')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get '?' exit=$rc"; }
[ ! -e "$WORK/jT/f1.txt" ] || _fail "trunk switch left f1.txt"

# the tag get: `?tags/v1` resolves in the LOCAL store and lands the tagged tree;
# the record tracks the tag ref pinned at its commit.
rc=$(gr_jget "$WORK/jT" '?tags/v1')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?tags/v1 exit=$rc"; }
gr_file_is "$WORK/jT/f1.txt" "V1"
gr_wtlog_has "$WORK/jT" "get\\?tags/v1#$VTIP"

pass
