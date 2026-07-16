#!/bin/sh
# test/get/behind-branch — GET-047: HISTORY BEHIND (3.2) × `?branch` (1.2):
# `get ?old` where old's tip is an ANCESTOR of the wt's base walks the wt
# BACK — the newer commit's files vanish, the older content returns, and the
# wtlog records `?old#<ancestor>`.
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"

# Publish `?old` at c1 (a bare `post ?old` is the explicit ref advance,
# DIS-076), then move on: a.txt A->A2, add z.txt, commit c2.  `old` stays at
# the ancestor c1 — a message-post never moves any ref.
cd "$SRC"
"$BE" post '?old' >/dev/null 2>&1 || _fail "publish ?old failed"
printf 'A2\n' > a.txt; printf 'Z\n' > z.txt
"$BE" put a.txt z.txt >/dev/null 2>&1
"$BE" post 'c2' >/dev/null 2>&1
C2=$(gr_tip_sha "$SRC")
[ -n "$C2" ] && [ "$C1" != "$C2" ] || _fail "c2 did not advance"

# Clone at c2, then switch to the ancestor branch: the wt must walk BACK.
gr_jclone "$SRC" "$WORK/jT"
gr_file_is "$WORK/jT/a.txt" "A2"
[ -e "$WORK/jT/z.txt" ] || _fail "clone did not land at c2"
rc=$(gr_jget "$WORK/jT" '?old')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?old exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A"          # older content restored
[ ! -e "$WORK/jT/z.txt" ] || _fail "walk-back left z.txt (a c2-only file)"
gr_wtlog_has "$WORK/jT" "get\?old#$C1"   # record: ?branch#<ancestor>

pass
