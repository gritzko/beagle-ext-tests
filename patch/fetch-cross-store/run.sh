#!/bin/sh
#  test/patch/fetch-cross-store — PATCH-011: `jab patch <transport-uri>` from a
#  wt whose OWN store lacks the source's newest commit must FETCH the source's
#  objects into the LOCAL shard first (get's wire/ingest leg, no wt touch),
#  then absorb ALL-LOCAL.  Fixture: TWO independent stores sharing t0 BY
#  CONSTRUCTION (the pinned SOURCE_DATE_EPOCH clock makes identical build
#  steps mint identical shas — no wire clone needed):
#
#      store a:  t0 ── t1      (t1 edits line 3)     ← the SOURCE
#      store b:  t0 ── b1      (b1 edits line 1)     ← the wt we patch
#
#  `jab patch file:<a-store>` from b's wt fetches t1's objects into b's
#  shard, pins (ours=b1, theirs=t1, fork=t0) and weave-merges f.txt to the
#  disjoint union 'A b C'.  A DEAD source refuses LOUDLY (PATCHFETCH) with
#  no wt mutation and no patch row.
. "$(dirname "$0")/../../lib/patchcase.sh"

#  Store a (the source): t0, then t1 edits line 3.
A="$WORK/a"; mkdir -p "$A/.be"
cd "$A"
printf 'a\nb\nc\n' > f.txt
_boot 't0'
printf 'a\nb\nC\n' > f.txt
_ci 't1 edit line 3' f.txt
T1=$(_tip '')

#  Store b (the wt we patch): the SAME t0 by construction, then its own
#  line-1 edit — an INDEPENDENT store whose shard lacks t1.
B="$WORK/b"; mkdir -p "$B/.be"
cd "$B"
printf 'a\nb\nc\n' > f.txt
_boot 't0'
printf 'A\nb\nc\n' > f.txt
_ci 'b1 edit line 1' f.txt
#  A jab-seeded primary is a FLAT single-shard store: the shard IS `.be`.
NLOGS=$(ls "$B"/.be/*.keeper | wc -l)
KBYTES=$(cat "$B"/.be/*.keeper | wc -c)   # JS-117: append = same logs, more bytes

#  TEST-003 rolling-idx quirk: drop stale keeper.idx in BOTH stores pre-op.
rm -f "$A"/.be/*.keeper.idx "$B"/.be/*.keeper.idx

#  The fetch leg: patch the TRANSPORT uri of a from b's wt.
# PATCH spec 2026-07-17: RED until the bang-less `?<sha>` recorded row lands
( cd "$B" && "$JABC" patch "file:$A/.be" ) \
    >"$WORK/js.out" 2>"$WORK/js.err" \
    || _fail "patch failed: $(cat "$WORK/js.err")"

#  A DEAD source must refuse loudly BEFORE any wt mutation / patch row.
if ( cd "$B" && "$JABC" patch "file:$WORK/void/.be" ) \
        >"$WORK/bad.out" 2>"$WORK/bad.err"; then
    _fail "dead source did not refuse: $(cat "$WORK/bad.out")"
fi

#  b is a PRIMARY wt (`.be/wtlog`); count/normalise its patch rows directly.
_rows() { grep -ac "$(printf '\tpatch\t')" "$B/.be/wtlog" 2>/dev/null || true; }
{
    echo "=== stdout ==="; cat "$WORK/js.out"
    echo "=== fetched ==="
    #  JS-117: the fetch tail-APPENDS to the existing sub-threshold log — the
    #  landing proof is byte growth with an UNCHANGED keeper-log count.
    if [ "$(cat "$B"/.be/*.keeper | wc -c)" -gt "$KBYTES" ] \
       && [ "$(ls "$B"/.be/*.keeper | wc -l)" -eq "$NLOGS" ]; then
        echo "objects appended to b's shard log"
    else
        echo "NO tail-append (logs $(ls "$B"/.be/*.keeper | wc -l)/$NLOGS)"
    fi
    echo "=== patch row ==="
    grep -a "$(printf '\tpatch\t')" "$B/.be/wtlog" | tail -1 | sed -E 's/^[^\t]*\t/T\t/'
    echo "rows=$(_rows)"
    echo "=== status ==="; _jstatus "$B"
    echo "=== file bytes ==="; _fbytes "$B" f.txt
    echo "=== dead source ==="
    if grep -q "PATCHFETCH" "$WORK/bad.err"; then
        echo "refused loudly"
    else
        echo "NO loud refusal: $(head -1 "$WORK/bad.err")"
    fi
    echo "rows=$(_rows)"
    _fbytes "$B" f.txt
} | golden_assert "$NAME" "$GOLDEN"
pass
