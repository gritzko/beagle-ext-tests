#!/bin/sh
# test/get/trunk-switch — GET-047 / GET.mkd 1.2 + DIS-073: a bare `get '?'`
# (PRESENT-empty query) from a NON-trunk position is an EXPLICIT trunk switch:
# the wt resets to the trunk ref's tip and the record is the trunk-shaped
# `?#<tip>` row — never a stay on the tracked branch (that is bare `get`).
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"
# DIS-076: publish the trunk EXPLICITLY (a bare post never mints a ref) so
# `get '?'` has a trunk ref to resolve — pinned at c1.
cd "$SRC"
"$BE" post '?' >/dev/null 2>&1 || _fail "publish trunk failed"

# advance the source PAST the trunk ref (c2 stays unpublished) so the clone pin
# (c2) differs from the trunk tip (c1) — the switch row is then unambiguous.
printf 'A2\n' > a.txt; printf 'Z\n' > z.txt
"$BE" put a.txt z.txt >/dev/null 2>&1
"$BE" post 'c2' >/dev/null 2>&1
C2=$(gr_tip_sha "$SRC")
[ "$C1" != "$C2" ] || _fail "c2 did not advance"

# clone at c2, then commit onto ?feat — the wt now sits OFF the trunk.
gr_jclone "$SRC" "$WORK/jT"
gr_file_is "$WORK/jT/a.txt" "A2"
cd "$WORK/jT"
printf 'F1\n' > f1.txt
"$JABC" put f1.txt >/dev/null 2>&1 || _fail "put f1.txt failed"
"$JABC" post '?feat' '#f1' >/dev/null 2>&1 || _fail "post ?feat failed"
"$JABC" post '?feat' >/dev/null 2>&1 || _fail "publish ?feat failed"
FEAT=$(gr_tip_sha "$WORK/jT")
[ -n "$FEAT" ] && [ "$FEAT" != "$C1" ] || _fail "no distinct feat tip"

# the switch: bare `get '?'` must land the TRUNK tip's tree (c1: a=A, no z, no
# f1) — not stay on feat, not the clone pin c2.
rc=$(gr_jget "$WORK/jT" '?')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get '?' exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A"
[ ! -e "$WORK/jT/z.txt" ]  || _fail "trunk switch left z.txt (a c2-only file)"
[ ! -e "$WORK/jT/f1.txt" ] || _fail "trunk switch left f1.txt (a feat-only file)"

# the record: the trunk-shaped `?#<trunk tip>` row (present-empty query + the
# resolved c1) — and `jab refs` labels the wt as trunk (`?`).
gr_wtlog_has "$WORK/jT" "get\\?#$C1"
LABEL=$( ( cd "$WORK/jT" && "$JABC" refs 2>/dev/null ) | sed -n 's/^branch: *//p' )
[ "$LABEL" = "?" ] || _fail "refs label after trunk switch: got [$LABEL] want [?]"

pass
