#!/bin/sh
# test/get/branch-relative — GET-047 / GET.mkd 1.2: `get ?branch` "can use
# branch paths, incl relative" — `?./child` enters the current branch's child,
# `?../sib` a sibling (dot-paths over the `/`-nested branch keys, the same
# family post's `?.`/`?..` resolveTarget speaks).
#
# MISMATCH at tip fe042740 (hence run.sh.broken, not registered): get's
# inRepoSeed passes the query VERBATIM to resolveRef — no dot-path resolution
# against the current branch — so both relative forms die while the absolute
# spellings work.  Observed (topology feat / feat/child / feat/sib all
# published, wt on ?feat):
#   get '?./child' -> rc=1 "JS exception: be get: cannot resolve ?./child"
#   get '?../sib'  -> rc=1 "JS exception: be get: cannot resolve ?../sib"
#   get '?feat/child' / '?feat/sib' -> rc=0 (absolute forms fine).
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"

gr_jclone "$SRC" "$WORK/jT"
cd "$WORK/jT"

# topology: ?feat, its child ?feat/child, its sibling ?feat/sib — each a real
# commit (message-post onto the branch) + an EXPLICIT publish (DIS-076).
printf 'F1\n' > f1.txt
"$JABC" put f1.txt >/dev/null 2>&1 || _fail "put f1.txt failed"
"$JABC" post '?feat' '#f1' >/dev/null 2>&1 || _fail "post ?feat failed"
"$JABC" post '?feat' >/dev/null 2>&1 || _fail "publish ?feat failed"

printf 'CH\n' > ch.txt
"$JABC" put ch.txt >/dev/null 2>&1 || _fail "put ch.txt failed"
"$JABC" post '?feat/child' '#ch' >/dev/null 2>&1 || _fail "post ?feat/child failed"
"$JABC" post '?feat/child' >/dev/null 2>&1 || _fail "publish ?feat/child failed"
CHTIP=$(gr_tip_sha "$WORK/jT")

rc=$(gr_jget "$WORK/jT" '?feat')          # back to the parent for the sibling
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?feat exit=$rc"; }
printf 'SB\n' > sb.txt
"$JABC" put sb.txt >/dev/null 2>&1 || _fail "put sb.txt failed"
"$JABC" post '?feat/sib' '#sb' >/dev/null 2>&1 || _fail "post ?feat/sib failed"
"$JABC" post '?feat/sib' >/dev/null 2>&1 || _fail "publish ?feat/sib failed"
SBTIP=$(gr_tip_sha "$WORK/jT")
[ -n "$CHTIP" ] && [ -n "$SBTIP" ] && [ "$CHTIP" != "$SBTIP" ] || _fail "bad topology tips"

# fixture sanity: the ABSOLUTE spellings resolve (so a relative failure below
# is the dot-path gap, not a missing ref).
rc=$(gr_jget "$WORK/jT" '?feat/child')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "absolute ?feat/child exit=$rc"; }
rc=$(gr_jget "$WORK/jT" '?feat')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?feat exit=$rc"; }

# --- 1. `?./child` from ?feat enters feat/child ------------------------------
rc=$(gr_jget "$WORK/jT" '?./child')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?./child exit=$rc"; }
gr_file_is "$WORK/jT/ch.txt" "CH"
gr_wtlog_has "$WORK/jT" "child#$CHTIP"

# --- 2. `?../sib` from ?feat/child enters the sibling feat/sib ---------------
rc=$(gr_jget "$WORK/jT" '?../sib')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?../sib exit=$rc"; }
gr_file_is "$WORK/jT/sb.txt" "SB"
[ ! -e "$WORK/jT/ch.txt" ] || _fail "?../sib left ch.txt (a feat/child-only file)"
gr_wtlog_has "$WORK/jT" "sib#$SBTIP"

pass
