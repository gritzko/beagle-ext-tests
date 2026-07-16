#!/bin/sh
# DIS-077 test/put/ref-set-detached — `put ?<40hex>` on a DETACHED worktree.
# Pre-fix, the set-cur arm keyed its ref write off cur's recorded query;
# detached, that query IS a 40-hex sha, so `put ?<sha2>` minted a ref
# literally NAMED `<sha1>` (a sha-named branch, addressable by nothing).
# RULED (gritzko 2026-07-15): the QUERY names a ref; a bare sha is not a
# trackable thing.  Detached, `put ?<40hex>` must REFUSE LOUDLY, naming the
# base-setting `put #<hex>` form; NO ref row is written and cur does not move.
. "$(dirname "$0")/../putcase.sh"

# T1 on trunk, a ?feat label at T1, then trunk advances to T2 — T1 and T2 are
# both resolvable commits and differ (the ref-set-sha topology).
seed_baseline 'printf "A\n" > a.txt'
( cd "$BASE" \
  && "$BE" put '?feat' >/dev/null 2>&1 \
  && sleep 0.02 && printf "A2\n" > a.txt \
  && "$BE" put a.txt   >/dev/null 2>&1 \
  && "$BE" post t2     >/dev/null 2>&1 )
T2=$("$JABC" "$(dirname "$0")/../tipsha.js" "$BASE")
T1=$("$JABC" "$(dirname "$0")/../parentsha.js" "$BASE")
[ -n "$T1" ] && [ -n "$T2" ] && [ "$T1" != "$T2" ] || _fail "could not resolve T1/T2"

fork_pair
# DETACH the wt at T1 (`get ?<sha>` writes the D2 detached record: the sha in
# the QUERY, empty fragment — the record whose query the pre-fix arm keyed on).
( cd "$JS" && "$JABC" get "?$T1" ) >/dev/null 2>&1 || _fail "could not detach at T1"
# dumprows emits via io.log (stderr) with blank spacer lines — fold 2>&1, count
# non-blank via awk (always exit 0, set -e-safe).  TEST-003: jab repos are
# unnamed single-shard — refs live at .be/refs when no named subshard exists.
_refdump() {
    _sh=$(ls -d "$1"/.be/*/ 2>/dev/null | grep -v '\.be/\.' | head -1)
    if [ -n "${_sh:-}" ] && [ -f "$_sh/refs" ]; then _rf="$_sh/refs"
    elif [ -f "$1/.be/refs" ]; then _rf="$1/.be/refs"
    else return 0; fi
    "$JABC" "$_CASE/../dumprows.js" "$_rf" 2>&1
}
_nrefrows() { _refdump "$1" | awk 'NF{n++} END{print n+0}'; }
NREF0=$(_nrefrows "$JS")
[ "$NREF0" -ge 1 ] || _fail "no refs rows in the fork (vacuous count)"

rc=0
( cd "$JS" && "$JABC" put "?$T2" ) >"$WORK/put.out" 2>"$WORK/put.err" || rc=$?

# 1. Loud refusal, pointing at the `#<hex>` base-set form.
[ "$rc" -ne 0 ] || _fail "detached put ?<40hex> exited 0 (keyed a ref off cur):
$(cat "$WORK/put.out" "$WORK/put.err")"
grep -q '#' "$WORK/put.err" \
    || _fail "refusal does not name the #<hex> base form: $(cat "$WORK/put.err")"
# 2. NO sha-named ref: no refs row keyed by the detached cur's own 40-hex.
_refdump "$JS" | grep -qF "?$T1#" \
    && _fail "minted a sha-named ref keyed <40hex> (off the detached cur):
$(_refdump "$JS")"
# 3. No refs row at all was appended (trunk did not silently advance either).
NREF1=$(_nrefrows "$JS")
[ "$NREF1" -eq "$NREF0" ] || _fail "refs rows grew $NREF0 -> $NREF1 (a ref moved):
$(_refdump "$JS")"
# 4. cur stays detached at T1.
CUR=$( ( cd "$JS" && "$JABC" refs ) | sed -n 's/^cur: *//p' )
[ "$CUR" = "$T1" ] || _fail "cur moved: $CUR != $T1"

pass
