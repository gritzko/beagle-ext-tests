#!/bin/sh
# test/patch/query-line — PATCH.mkd 2026-07-17: `?<ref>` and `?<hash>` absorb
# the WHOLE missing commit line up to that ref/hash (the old `?br!` whole-
# branch URI bang is RETIRED; `?ref` always takes the whole line, never a
# NEXT-one-commit step).  Topology:
#
#       T0 ── T1                    ← cur (trunk): T1 edits line 5
#         \
#          F1 ── F2 ── F3           ← ?feat: edits line 2, 3, 4 (one each)
#
#  Leg A `patch ?feat`  (ref/tag slot): ALL of F1..F3 land — the merged f.txt
#         carries lines 2,3,4 from theirs + line 5 from ours; the row records
#         the line TIP (F3).  A NEXT-one-commit implementation would land F1
#         only (no F-l3/F-l4) — that is the red this leg guards against.
#  Leg B `patch ?<F2>`  (hash in the ?query slot): the line UP TO F2 — F1+F2
#         land, F3 does NOT; the row records F2.
#
#  GREEN today: jab's absorb is triple-based (fork=LCA, theirs=the resolved
#  tip), so the whole missing stack lands for both slots (verified by probe).
. "$(dirname "$0")/../../lib/patchspec.sh"

ORG="$WORK/org"; mkdir -p "$ORG/.be"
cd "$ORG"
printf 'l1\nl2\nl3\nl4\nl5\n' > f.txt
_boot 't0'; T0=$BOOT
_fork feat
_sw feat
printf 'l1\nF-l2\nl3\nl4\nl5\n' > f.txt;       _ci 'F1 l2' f.txt
F1=$(_tip)
printf 'l1\nF-l2\nF-l3\nl4\nl5\n' > f.txt;     _ci 'F2 l3' f.txt
F2=$(_tip)
printf 'l1\nF-l2\nF-l3\nF-l4\nl5\n' > f.txt;   _ci 'F3 l4' f.txt
F3=$(_tip)
_trunk
printf 'l1\nl2\nl3\nl4\nT-l5\n' > f.txt;       _ci 't1 l5' f.txt
T1=$(_tip)
cd /

# ---- leg A: `?feat` — the whole missing line lands, row records the tip ----
A="$WORK/a"; ps_clone "$A"
( cd "$A" && "$JABC" patch '?feat' ) > "$WORK/a.out" 2> "$WORK/a.err" \
    || _fail "patch ?feat exited non-zero: $(cat "$WORK/a.err")"
_want='l1
F-l2
F-l3
F-l4
T-l5'
[ "$(cat "$A/f.txt")" = "$_want" ] \
    || _fail "?feat did not absorb the WHOLE line (one-commit NEXT?):
$(cat "$A/f.txt")"
ps_patch_rows "$A" | grep -q "$F3" \
    || _fail "?feat row does not record the line tip $F3:
$(ps_patch_rows "$A")"
echo "ok   A: ?feat absorbed F1..F3 (whole line), row records the tip"

# ---- leg B: `?<hash>` — the line up to F2; F3 stays out -------------------
B="$WORK/b"; ps_clone "$B"
( cd "$B" && "$JABC" patch "?$F2" ) > "$WORK/b.out" 2> "$WORK/b.err" \
    || _fail "patch ?<F2> exited non-zero: $(cat "$WORK/b.err")"
_want='l1
F-l2
F-l3
l4
T-l5'
[ "$(cat "$B/f.txt")" = "$_want" ] \
    || _fail "?<hash> did not absorb the line up to F2 exactly:
$(cat "$B/f.txt")"
ps_patch_rows "$B" | grep -q "$F2" \
    || _fail "?<hash> row does not record F2:
$(ps_patch_rows "$B")"
echo "ok   B: ?<F2-hash> absorbed F1+F2 only, row records F2"

pass
