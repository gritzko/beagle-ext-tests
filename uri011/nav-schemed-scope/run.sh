#!/bin/sh
# URI-011 test/uri011/nav-schemed-scope — a SCHEMED click-target spell
# (`diff://NAME/path`, a baked projector click-target) must scope to the NAMED
# tree, NOT the launch cwd; a bare `//NAME` (verb form) must scope too.
#
# NOTE (URI-012/URI-013): `status://NAME` is NOT a valid form — `status` is a VERB,
# not a scheme (views are verbs; only diff:/cat:/commit: bake as click-target
# schemes).  Typing `//NAME` on a status view composes `status //NAME` (leg a),
# never `status://NAME`; that stale leg (b) was dropped.  loop.js::authorityRepo
# scopes a scheme-LESS `//NAME` AND a schemed click-target (`diff://NAME/path`)
# off its authority.  SUT=loop (jab main.js); JS-ONLY.  Modelled on nav-navnone.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/uri011/nav-schemed-scope
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (it LAGS jab); locate jab and
# alias BE=$JABC so legacy `"$BE" post/put` seeds run jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "nav-schemed-scope: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
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
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true

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
# URI-014: the banner is the `word URI` spell — a no-authority bare status is the
# bare verb `status` (was `status:`; the verb left the scheme slot).
grep -q '^status$' "$WORK/s-bare.out" \
    || _fail "(d) bare status banner is not the bare 'status' (authority hijacked?):
$(cat "$WORK/s-bare.out")"
echo "ok: bare status stays cwd (no authority hijack)"

echo "PASS [$NAME]"
