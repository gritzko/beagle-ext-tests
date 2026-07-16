#!/bin/sh
# DIS-077 test/put/base-set — `put #<hex>` sets the worktree BASE (RULED,
# gritzko 2026-07-15: the FRAGMENT carries the base hash).  A wt-local motion:
# cur moves to the resolved commit, the TRACK is preserved, NO ref row is
# written, nothing is staged.  The recorded row is the get-row pin get.js
# already writes (D1 `?<track>#<sha>` attached / DIS-075 `#<sha>` detached), so the
# ONE attach reader (wtlog.attachedBranch, DIS-059) reads it back unchanged.
# Sub-cases: A full sha on trunk; B short hex; C detached stays detached;
# D attached to a named branch keeps that branch.
. "$(dirname "$0")/../putcase.sh"

# Two commits: T1 (parent) and T2 (trunk tip); a ?feat label at T1 for case D.
seed_baseline 'printf "A\n" > a.txt'
( cd "$BASE" \
  && "$BE" put '?feat' >/dev/null 2>&1 \
  && sleep 0.02 && printf "A2\n" > a.txt \
  && "$BE" put a.txt   >/dev/null 2>&1 \
  && "$BE" post t2     >/dev/null 2>&1 )
T2=$("$JABC" "$(dirname "$0")/../tipsha.js" "$BASE")
T1=$("$JABC" "$(dirname "$0")/../parentsha.js" "$BASE")
[ -n "$T1" ] && [ -n "$T2" ] && [ "$T1" != "$T2" ] || _fail "could not resolve T1/T2"

_cur()    { ( cd "$1" && "$JABC" refs ) | sed -n 's/^cur: *//p'; }
_branch() { ( cd "$1" && "$JABC" refs ) | sed -n 's/^branch: *//p'; }
# dumprows emits via io.log (stderr) with blank spacer lines — fold 2>&1, count
# non-blank via awk (always exit 0, set -e-safe).  TEST-003: jab repos are
# unnamed single-shard — refs live at .be/refs when no named subshard exists.
_count()   { awk 'NF{n++} END{print n+0}'; }
_refdump() {
    _sh=$(ls -d "$1"/.be/*/ 2>/dev/null | grep -v '\.be/\.' | head -1)
    if [ -n "${_sh:-}" ] && [ -f "$_sh/refs" ]; then _rf="$_sh/refs"
    elif [ -f "$1/.be/refs" ]; then _rf="$1/.be/refs"
    else return 0; fi
    "$JABC" "$_CASE/../dumprows.js" "$_rf" 2>&1
}
_nrefrows() { _refdump "$1" | _count; }
_nputrows() { _putrows "$1" 2>&1 | _count; }
_lastget()  { "$JABC" "$_CASE/../dumprows.js" "$1/.be/wtlog" get 2>&1 \
              | awk 'NF{last=$0} END{print last}'; }

# base_put CASE TARGET WANT_SHA — run `put #TARGET`, assert: exit 0, cur moves
# to WANT_SHA, no refs row appended, no put row staged (base-set stages NOTHING).
base_put() {
    _c=$1; _t=$2; _want=$3
    _nr0=$(_nrefrows "$JS"); _np0=$(_nputrows "$JS")
    [ "$_nr0" -ge 1 ] || _fail "($_c) no refs rows in the fork (vacuous count)"
    [ "$_np0" -ge 1 ] || _fail "($_c) no put rows in the fork (vacuous count)"
    ( cd "$JS" && "$JABC" put "#$_t" ) >"$WORK/$_c.out" 2>"$WORK/$_c.err" \
        || _fail "($_c) put #$_t failed:
$(cat "$WORK/$_c.out" "$WORK/$_c.err")"
    _got=$(_cur "$JS")
    [ "$_got" = "$_want" ] || _fail "($_c) base did not move: cur $_got != $_want"
    _nr1=$(_nrefrows "$JS")
    [ "$_nr1" -eq "$_nr0" ] || _fail "($_c) put #hex wrote a ref row ($_nr0 -> $_nr1):
$(_refdump "$JS")"
    _np1=$(_nputrows "$JS")
    [ "$_np1" -eq "$_np0" ] || _fail "($_c) put #hex STAGED rows ($_np0 -> $_np1):
$(_putrows "$JS" 2>&1)"
}

# A. attached (trunk) + full sha: base -> T1, still trunk, D1 pin row `?#<sha>`.
fork_pair
base_put A "$T1" "$T1"
[ "$(_branch "$JS")" = "?" ] || _fail "(A) track changed: $(_branch "$JS") != ?"
[ "$(_lastget "$JS")" = "get	?#$T1" ] \
    || _fail "(A) row is not the D1 trunk pin: $(_lastget "$JS")"

# B. short hex (8) resolves like everywhere else (store.resolveHexAny).
fork_pair
base_put B "$(printf %s "$T1" | cut -c1-8)" "$T1"

# C. DETACHED wt: the base moves, the wt STAYS detached — DIS-075's canonical
# detached record is `#<sha>` (query slot ABSENT), never the old `?<sha>`.
fork_pair
( cd "$JS" && "$JABC" get "?$T1" ) >/dev/null 2>&1 || _fail "(C) could not detach at T1"
base_put C "$T2" "$T2"
[ "$(_lastget "$JS")" = "get	#$T2" ] \
    || _fail "(C) row is not the DIS-075 detached record: $(_lastget "$JS")"

# D. attached to ?feat: the base moves, the TRACK stays ?feat (D1 pin row).
fork_pair
( cd "$JS" && "$JABC" get "?feat" ) >/dev/null 2>&1 || _fail "(D) could not attach ?feat"
base_put D "$T2" "$T2"
[ "$(_branch "$JS")" = "?feat" ] || _fail "(D) track changed: $(_branch "$JS") != ?feat"
[ "$(_lastget "$JS")" = "get	?feat#$T2" ] \
    || _fail "(D) row is not the D1 feat pin: $(_lastget "$JS")"

pass
