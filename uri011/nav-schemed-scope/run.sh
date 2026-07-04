#!/bin/sh
# URI-011 test/uri011/nav-schemed-scope — a SCHEMED nav spell (`status://NAME`,
# `diff://NAME/path`) must scope status/diff to the NAMED tree, NOT the launch cwd.
#
# REPRO of the DIS-060 authority leak on the bro pager RE-ENTRY: typing `//NAME`
# in the address bar makes the pager re-compose the spell as `<verb> <verb>://NAME`
# (verb + a SCHEMED URI carrying the authority).  loop.js::authorityRepo scopes a
# scheme-LESS `//NAME` but SKIPS the schemed form (its `u.scheme` guard), so
# be.repo stays the launch cwd → status prints the CWD tree's files (spurious
# `mis`/wrong content) and diff resolves the base against the WRONG tree ("all
# green").  status.js/diff.js::navScope re-scope be.repo/be.authority off the arg
# authority.  SUT=loop (jab main.js); JS-ONLY.  Modelled on test/uri011/nav-navnone.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/uri011/nav-schemed-scope
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "nav-schemed-scope: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-${JAB:-$_BIN/jab}}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "nav-schemed-scope: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "nav-schemed-scope: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/uri011/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink (jab's upward be/-scan).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# Force URI-011's OWN be/ (main.js) — never a cwd-scanned stale shard.
M="$BEDIR/main.js"

# SRC_ROOT = a scratch root with TWO trees: HERE (the launch cwd) + THERE (the
# named nav target), each with one DISTINCT `put`-staged file so a leak is
# unambiguous — the file NAME (status) and its CONTENT (diff) name the tree.  A
# fresh `.be/` shield + `put` needs no bootstrapped store (a bare `post` would).
export SRC_ROOT="$WORK"
mkdir -p "$WORK/HERE/.be" "$WORK/THERE/.be"
( cd "$WORK/HERE"  && printf 'HOMEMARK\n'  > only-here.txt \
    && "$JABC" "$M" put only-here.txt  >/dev/null 2>&1 ) || _fail "HERE seed failed"
( cd "$WORK/THERE" && printf 'AWAYMARK\n' > only-there.txt \
    && "$JABC" "$M" put only-there.txt >/dev/null 2>&1 ) || _fail "THERE seed failed"

# (a) STATUS scheme-less `//THERE` from HERE scopes to THERE (control — already worked).
( cd "$WORK/HERE" && "$JABC" "$M" status '//THERE' --plain ) >"$WORK/s-none.out" 2>&1 || true
grep -q 'only-there.txt' "$WORK/s-none.out" \
    || _fail "(a) status //THERE did not show THERE's file:
$(cat "$WORK/s-none.out")"
grep -q 'only-here.txt' "$WORK/s-none.out" \
    && _fail "(a) status //THERE LEAKED HERE's file:
$(cat "$WORK/s-none.out")"
echo "ok: status //THERE scopes to THERE"

# (b) STATUS schemed `status://THERE` (the pager-composed spell) must ALSO scope
#     to THERE — the bug rendered HERE (cwd).
( cd "$WORK/HERE" && "$JABC" "$M" status 'status://THERE' --plain ) >"$WORK/s-sch.out" 2>&1 || true
grep -q 'only-there.txt' "$WORK/s-sch.out" \
    || _fail "(b) status status://THERE did not show THERE's file (leaked to cwd?):
$(cat "$WORK/s-sch.out")"
grep -q 'only-here.txt' "$WORK/s-sch.out" \
    && _fail "(b) status status://THERE LEAKED HERE's file (the DIS-060 leak):
$(cat "$WORK/s-sch.out")"
grep -q 'status://THERE' "$WORK/s-sch.out" \
    || _fail "(b) status status://THERE lost the //THERE authority in its banner:
$(cat "$WORK/s-sch.out")"
echo "ok: status status://THERE scopes to THERE (schemed pager spell)"

# (c) DIFF schemed `diff://THERE/only-there.txt` reads THERE's wt blob, not HERE's.
#     The put-staged file has no committed base → shown as wholly-added, so the
#     line CONTENT (`AWAYMARK` vs `HOMEMARK`) is the leak discriminator.
( cd "$WORK/HERE" && "$JABC" "$M" diff 'diff://THERE/only-there.txt' --plain ) >"$WORK/d-sch.out" 2>&1 || true
grep -q 'AWAYMARK' "$WORK/d-sch.out" \
    || _fail "(c) diff diff://THERE/only-there.txt did not read THERE's blob:
$(cat "$WORK/d-sch.out")"
grep -q 'HOMEMARK' "$WORK/d-sch.out" \
    && _fail "(c) diff diff://THERE/... LEAKED HERE's content (base against cwd):
$(cat "$WORK/d-sch.out")"
echo "ok: diff diff://THERE/... scopes to THERE (schemed pager spell)"

# (d) BARE status from HERE (no authority) stays cwd — the leak fix must not
#     hijack a plain call.
( cd "$WORK/HERE" && "$JABC" "$M" status --plain ) >"$WORK/s-bare.out" 2>&1 || true
grep -q 'only-here.txt' "$WORK/s-bare.out" \
    || _fail "(d) bare status from HERE did not show HERE's file:
$(cat "$WORK/s-bare.out")"
grep -q '^status:$' "$WORK/s-bare.out" \
    || _fail "(d) bare status banner is not the bare 'status:' (authority hijacked?):
$(cat "$WORK/s-bare.out")"
echo "ok: bare status stays cwd (no authority hijack)"

echo "PASS [$NAME]"
