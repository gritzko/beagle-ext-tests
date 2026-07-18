#!/bin/sh
# PATCH spec 2026-07-17: RED until no-op patch prints header only
#
# test/patch/noop-behind — PATCH.mkd §Ancestor-skip: "a target behind or
# equal to cur has an empty missing set — nothing to do".  Fixture: trunk
# t0 -> t1 (cur = t1, f.txt+g.txt edited on the way); leg A patches `?<t0>`
# (BEHIND — an ancestor of cur), leg B `?<t1>` (EQUAL).  Both must be a
# clean no-op: exit 0, NO wt byte change, NO `patch` wtlog row, and (RULING
# 2026-07-17 on the banner shape) the report is the `?<sha>` HEADER LINE
# ONLY — zero rows after it, no `mod` listing.
#
# TODAY: the noop gate (exit 0 / no row / no restamp) holds, but the BEHIND
# leg still prints a `mod <path>` row for every ours-changed path (with
# fork==theirs an ours-changed file reads "only ours" and emits) — that
# header-only assert is the intended spec-first red.
. "$(dirname "$0")/../../lib/patchspec.sh"

ORG="$WORK/org"; mkdir -p "$ORG/.be"
cd "$ORG"
printf 'f base\n' > f.txt
printf 'g base\n' > g.txt
_boot 't0'; T0=$BOOT
printf 'f t1\n' > f.txt
printf 'g t1\n' > g.txt
_ci 't1' f.txt g.txt
T1=$(_tip)
cd /

A="$WORK/a"; ps_clone "$A"
_pre_f=$(cat "$A/f.txt"); _pre_g=$(cat "$A/g.txt")

# ---- leg A: target BEHIND cur (t0 is an ancestor of cur=t1) ---------------
( cd "$A" && "$JABC" patch "?$T0" ) > "$WORK/a.out" 2> "$WORK/a.err" \
    || _fail "patch of a BEHIND target must be a clean no-op exit 0, got: $(cat "$WORK/a.err")"
[ "$(cat "$A/f.txt")" = "$_pre_f" ] || _fail "behind-target patch changed f.txt"
[ "$(cat "$A/g.txt")" = "$_pre_g" ] || _fail "behind-target patch changed g.txt"
[ -z "$(ps_patch_rows "$A")" ] \
    || _fail "behind-target patch recorded a row: $(ps_patch_rows "$A")"
head -1 "$WORK/a.out" | grep -q "?$T0" \
    || _fail "behind-target banner lost the ?<sha> header: $(cat "$WORK/a.out")"
#  RULING 2026-07-17: header line ONLY — zero rows (no `mod` listing).
[ "$(sed -n '2,$p' "$WORK/a.out" | grep -vc '^$')" = 0 ] \
    || _fail "behind-target banner grew rows past the header (ruling: header only):
$(cat "$WORK/a.out")"
echo "ok   A: behind target — exit 0, bytes intact, no patch row, header-only banner"

# ---- leg B: target EQUAL to cur -------------------------------------------
( cd "$A" && "$JABC" patch "?$T1" ) > "$WORK/b.out" 2> "$WORK/b.err" \
    || _fail "patch of an EQUAL target must be a clean no-op exit 0, got: $(cat "$WORK/b.err")"
[ "$(cat "$A/f.txt")" = "$_pre_f" ] || _fail "equal-target patch changed f.txt"
[ "$(cat "$A/g.txt")" = "$_pre_g" ] || _fail "equal-target patch changed g.txt"
[ -z "$(ps_patch_rows "$A")" ] \
    || _fail "equal-target patch recorded a row: $(ps_patch_rows "$A")"
head -1 "$WORK/b.out" | grep -q "?$T1" \
    || _fail "equal-target banner lost the ?<sha> header: $(cat "$WORK/b.out")"
#  RULING 2026-07-17: header line ONLY — zero rows after it.
[ "$(sed -n '2,$p' "$WORK/b.out" | grep -vc '^$')" = 0 ] \
    || _fail "equal-target banner grew rows past the header (ruling: header only):
$(cat "$WORK/b.out")"
echo "ok   B: equal target — exit 0, bytes intact, no patch row, header-only banner"

pass
