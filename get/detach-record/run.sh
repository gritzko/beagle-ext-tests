#!/bin/sh
# test/get/detach-record — DIS-075: the canonical DETACHED record is `#<sha>`
# (query slot ABSENT, base in the fragment; laws #1+#3 of DIS-071).  `?<sha>`
# is the detach ARGUMENT (GET.mkd:11,24), never the record.  Asserts:
#   1. `get ?<sha>` records `get#<sha>` — NOT the argument shape `?<sha>`.
#   2. a detached `post` records `post#<sha>` — NOT trunk-shaped `?#<sha>`.
#   3. `jab refs` labels the wt detached (the cur sha), not `?` (trunk).
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
gr_jclone "$SRC" "$WORK/jT"
TIP=$(gr_tip_sha "$SRC")
[ -n "$TIP" ] || _fail "no tip sha"

# --- 1. D2 detach records `#<sha>` (fragment), not `?<sha>` (query) ---------
rc=$(gr_jget "$WORK/jT" "?$TIP")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?<sha> exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A"
gr_wtlog_has "$WORK/jT" "get#$TIP"
gr_wtraw "$WORK/jT" | grep -qE "get\\?$TIP" \
    && _fail "detach recorded the ARGUMENT ?<sha>, not the record #<sha>" || true

# --- 2. a detached commit records `post#<sha>`, never trunk-shaped `?#` -----
( cd "$WORK/jT" && printf 'A2\n' > a.txt && "$JABC" put a.txt >/dev/null 2>&1 \
  && "$JABC" post '#c2' ) >"$WORK/p.out" 2>"$WORK/p.err" \
    || _fail "detached post failed: $(cat "$WORK/p.err")"
NEW=$(gr_tip_sha "$WORK/jT")
[ -n "$NEW" ] && [ "$NEW" != "$TIP" ] || _fail "detached post did not advance cur"
gr_wtlog_has "$WORK/jT" "post#$NEW"
gr_wtraw "$WORK/jT" | grep -qE "post\\?#$NEW" \
    && _fail "detached post recorded trunk-shaped ?#<sha>, not #<sha>" || true

# --- 3. `jab refs` agrees with post's own detach guard: NOT the trunk `?` ---
LABEL=$( ( cd "$WORK/jT" && "$JABC" refs 2>/dev/null ) | sed -n 's/^branch: *//p' )
[ "$LABEL" != "?" ] || _fail "jab refs labels a DETACHED wt as trunk (?)"
[ "$LABEL" = "?$NEW" ] \
    || _fail "jab refs detached label: got [$LABEL] want [?$NEW]"

pass
