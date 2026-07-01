#!/bin/sh
# test/js/put/ref-set-sha — `be put ?<40hex>` (bare full-sha set-cur, the
# reflog escape hatch) parity in BOTH sub-cases (DIS-050):
#   A. sha == cur's OWN branch tip — the "set to current value" no-op.
#   B. sha != cur tip but a resolvable sibling tip — a genuine ref reset.
# `?<40hex>` rewrites cur's branch OUTRIGHT to the resolved sha.  JAB-003:
# each sub-case snapshots its own golden (refs rows + empty stdout); we also
# count the refs rows so the case can never pass vacuously (a no-op case must
# NOT mask a divergence).
. "$(dirname "$0")/../putcase.sh"

# refs-row counter: count `post`/`delete` rows in a side's project shard.
_nrefs() {
    _sh=$(ls -d "$1"/.be/*/ 2>/dev/null | grep -v '\.be/\.' | head -1)
    [ -n "${_sh:-}" ] && [ -f "$_sh/refs" ] || { echo 0; return; }
    awk 'BEGIN{RS="\t";n=0} $0=="post"||$0=="delete"{n++} END{print n}' "$_sh/refs"
}

# Minimal topology: commit T1 on trunk, fork ?feat at T1 (a sibling tip),
# then advance trunk to T2.  cur stays trunk throughout, so cur's tip (T2)
# and the ?feat tip (T1) DIFFER and BOTH are resolvable.
seed_baseline 'printf "A\n" > a.txt'
( cd "$BASE" \
  && "$BE" put '?./feat'  >/dev/null 2>&1 \
  && sleep 0.02 && printf "A2\n" > a.txt \
  && "$BE" put a.txt      >/dev/null 2>&1 \
  && "$BE" post t2        >/dev/null 2>&1 )

CUR=$("$JABC" "$(dirname "$0")/../tipsha.js" "$BASE")
FEAT=$("$JABC" "$(dirname "$0")/../tipsha.js" "$BASE" feat)
[ -n "$CUR" ]  || _fail "could not resolve cur tip sha"
[ -n "$FEAT" ] || _fail "could not resolve ?feat tip sha"
[ "$CUR" != "$FEAT" ] || _fail "cur tip and ?feat tip unexpectedly equal"
BASE_N=$(_nrefs "$BASE")

# A. sha == cur tip: set cur's branch to the sha it already holds.  JAB-003:
# no-op case snapshots its own golden; refs count must stay at baseline.
fork_pair
GOLDEN="$_CASE/A.golden.out" put_both "?$CUR"
JA=$(_nrefs "$JS")
[ "$JA" -eq "$BASE_N" ] || _fail "CASE A must be a no-op (base=$BASE_N got=$JA)"

# B. sha != cur tip: reset cur's branch OUTRIGHT to the ?feat tip.  JAB-003: a
# real move must add exactly one refs row past the baseline; own golden.
fork_pair
GOLDEN="$_CASE/B.golden.out" put_both "?$FEAT"
JB=$(_nrefs "$JS")
[ "$JB" -eq $((BASE_N + 1)) ] \
    || _fail "CASE B must add one refs row (base=$BASE_N got=$JB)"

pass
