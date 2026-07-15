#!/bin/sh
# test/get/branch-bare — DIS-073 D3': a bare `be get` (and `!`) on a wt tracking
# a NON-trunk branch must FF to that BRANCH's tip, not the trunk — and the
# recorded wtlog row's track (branch) and base (sha) must agree.  Repro: a wt
# on ?feat, behind feat's real tip (advanced by a SIBLING wt off the same
# store); a bare `be get` must pull feat's newest content, not the trunk's.
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"

# jT: clone at trunk, then commit onto ?feat — cur is now ATTACHED to feat@Cf1
# (a real commit with a message retargets cur's wtlog track, DIS-054/061).
gr_jclone "$SRC" "$WORK/jT"
cd "$WORK/jT"
printf 'FEAT1\n' > f1.txt
"$JABC" put f1.txt >/dev/null 2>&1 || _fail "put f1.txt failed"
"$JABC" post '?feat' '#feat1' >/dev/null 2>&1 || _fail "post ?feat failed"
gr_wtlog_has "$WORK/jT" 'post\?feat#'

# jT2: a SEPARATE wt cloned straight onto ?feat off the SAME store, advances
# feat FURTHER without touching jT's wtlog — feat's real tip outruns jT's cur.
mkdir -p "$WORK/jT2"
( cd "$WORK/jT2" && "$JABC" get "file://$SRC/.be?feat" ) >/dev/null 2>&1 \
    || _fail "jT2 clone at ?feat failed"
cd "$WORK/jT2"
gr_file_is "$WORK/jT2/f1.txt" "FEAT1"          # confirms jT2 landed on feat, not trunk
printf 'FEAT2\n' > f2.txt
"$JABC" put f2.txt >/dev/null 2>&1 || _fail "put f2.txt failed"
"$JABC" post '#feat2' >/dev/null 2>&1 || _fail "post feat2 (jT2) failed"

# feat's real tip (Cf2) per the shared store's refs — jT's cur is still Cf1.
FEATTIP=$(od -An -c "$SRC/.be/refs" 2>/dev/null | tr -d ' \n' \
          | grep -oE '\?feat#[0-9a-f]{40}' | tail -1 | sed 's/^?feat#//')
[ -n "$FEATTIP" ] || _fail "cannot read feat's tip from $SRC/.be/refs"

# The RED assertion: a bare `be get` in jT must FF to feat's tip (f2.txt
# appears) — NOT the trunk's C1 (which would drop f1.txt and never show f2.txt).
cd "$WORK/jT"
rc=$(gr_jget "$WORK/jT" '.')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "bare get exit=$rc"; }
gr_file_is "$WORK/jT/f1.txt" "FEAT1"
gr_file_is "$WORK/jT/f2.txt" "FEAT2"

# The recorded wtlog row's track (branch) and base (sha) must AGREE: `?feat`
# paired with feat's REAL tip, never the trunk's C1.
gr_wtlog_has "$WORK/jT" "get\\?feat#$FEATTIP"
gr_wtraw "$WORK/jT" | grep -qE "get\\?feat#$C1\$" \
    && _fail "bare get recorded ?feat but resolved the TRUNK tip ($C1) — DIS-073" || true

pass
