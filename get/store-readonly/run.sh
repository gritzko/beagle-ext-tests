#!/bin/sh
# test/get/store-readonly — GET-047 / GET.mkd 1.6: the schemed network leg is
# "the only pattern that changes something in the store".  Negative control:
# a bare FF, a ?branch switch, a `?` trunk switch and a narrow restore run in a
# secondary wt leave the SOURCE STORE byte-identical (wtlog rows land in the
# wt's own `.be` redirect file, never in the store).
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"
cd "$SRC"
"$BE" post '?' >/dev/null 2>&1 || _fail "publish trunk@c1 failed"

# advance to c2, publish trunk@c2 + a named branch feat@c2 — the refs the
# clone's gets will resolve.  ALL store writes happen before the snapshot.
printf 'A2\n' > a.txt; printf 'Z\n' > z.txt
"$BE" put a.txt z.txt >/dev/null 2>&1
"$BE" post 'c2' >/dev/null 2>&1
C2=$(gr_tip_sha "$SRC")
[ "$C1" != "$C2" ] || _fail "c2 did not advance"
"$BE" post '?' >/dev/null 2>&1 || _fail "publish trunk@c2 failed"
"$BE" post '?feat' >/dev/null 2>&1 || _fail "publish feat@c2 failed"

# clone BEHIND the trunk (pinned at c1) so the bare get below has a real FF.
mkdir -p "$WORK/jT"
( cd "$WORK/jT" && "$JABC" get "file://$SRC/.be#$C1" ) >/dev/null 2>&1 \
    || _fail "clone at #c1 failed"
gr_file_is "$WORK/jT/a.txt" "A"

# snapshot the store: every file's md5 (name + bytes; adds/dels/rewrites all show).
store_snap() { ( cd "$SRC/.be" && find . -type f | sort | xargs md5sum ); }
store_snap > "$WORK/store.before"
[ -s "$WORK/store.before" ] || _fail "empty store snapshot"

# 1. bare FF (AHEAD): c1 -> trunk tip c2.
rc=$(gr_jget "$WORK/jT")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "bare get exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A2"
gr_file_is "$WORK/jT/z.txt" "Z"
# 2. ?branch switch (feat@c2), then back to the trunk.
rc=$(gr_jget "$WORK/jT" '?feat')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?feat exit=$rc"; }
rc=$(gr_jget "$WORK/jT" '?')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ? exit=$rc"; }
# 3. narrow restore of a dirtied file from the baseline.
printf 'DIRTY\n' > "$WORK/jT/a.txt"
rc=$(gr_jget "$WORK/jT" a.txt)
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get a.txt exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A2"

store_snap > "$WORK/store.after"
cmp -s "$WORK/store.before" "$WORK/store.after" || {
    echo "--- store drift ---" >&2
    diff "$WORK/store.before" "$WORK/store.after" >&2 || true
    _fail "local gets CHANGED the store — only the schemed leg may write it"
}

pass
