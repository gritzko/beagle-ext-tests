#!/bin/sh
# LIST-001 test/list — the `list:<path>` view END-TO-END over the resident loop:
# `:list <path>` must DISPATCH as a view (not degrade to ls), fusing ls's wt
# marker with each entry's LAST COMMIT (summary + short rel-age), files AND dirs.
#
# A 3-commit fixture (a.txt seeded @C0, b.txt added @C1, sub/x.txt edited @C2)
# plus ONE uncommitted edit to a.txt.  We drive `jab list list: --plain` and
# assert the FUSED row shape (the age column is wall-clock volatile → normalised
# away for the compare):
#   * a.txt  → wt marker `mod` (the uncommitted edit) + its LAST commit C0 summary
#   * b.txt  → clean `eq` + its add-commit C1 summary
#   * sub/   → a `dir` row + the NEWEST commit UNDER it (C2), NOT its C0 seed
#   * every entry carries a non-empty rel-age token, and the scheme dispatched
#     as `list` (the banner is `list`, not an `ls` listing).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)              # test/list/e2e
_ROOT=$(cd "$_CASE/../.." && pwd)                 # be/test
# TEST-003: jab-only — native `be` is RETIRED (it LAGS jab); locate jab and
# alias BE=$JABC so legacy `"$BE" post/put` seeds run jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "list: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"        # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "list: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/views/list/list.js" ] || { echo "list: SKIP — no views/list/list.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "list: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/list/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink so bareword `jab list`
# resolves the extension via jab's upward be/-scan from the worktree cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# 3-commit fixture + an uncommitted edit to a.txt (the wt overlay).
WT="$WORK/wt"; mkdir -p "$WT/.be" "$WT/sub"
cd "$WT"
printf 'A0\n' > a.txt
printf 'X0\n' > sub/x.txt
"$BE" post 'C0 seed a and sub' >/dev/null 2>&1 || _fail "post C0"
printf 'B1\n' > b.txt
"$BE" put b.txt >/dev/null 2>&1; "$BE" post 'C1 add b' >/dev/null 2>&1 || _fail "post C1"
printf 'X2\n' > sub/x.txt
"$BE" put sub/x.txt >/dev/null 2>&1; "$BE" post 'C2 edit sub' >/dev/null 2>&1 || _fail "post C2"
printf 'A0-dirty\n' >> a.txt            # uncommitted → a.txt reads `mod`

( cd "$WT" && "$JABC" list "list:" --plain ) >"$WORK/out" 2>"$WORK/err" \
    || _fail "jab list: failed ($(cat "$WORK/err"))"
[ -s "$WORK/out" ] || _fail "jab list: emitted ZERO bytes"

# The banner is the `list` scheme (dispatched as a view, NOT an `ls` listing).
head -n1 "$WORK/out" | grep -q '^list' || { cat "$WORK/out" >&2; _fail "banner is not the list scheme (degraded to ls?)"; }

# Each entry carries a rel-age token (Ns/Nm/Nh/Nd/Ny) at the row tail — assert
# its presence, THEN strip it so the summary compare is age-agnostic.
for _row in 'mod a.txt' 'eq  b.txt' 'dir sub/'; do
    grep -q "^$_row " "$WORK/out" || { cat "$WORK/out" >&2; _fail "missing entry row: $_row"; }
done
grep -qE '[0-9]+[smhdy]$' "$WORK/out" || { cat "$WORK/out" >&2; _fail "no rel-age column"; }

# The FUSE: each entry's row carries its LAST-commit summary; the DIR gets the
# NEWEST commit under it (C2), not its C0 seed.
grep -q '^mod a.txt .*C0 seed a and sub' "$WORK/out" || { cat "$WORK/out" >&2; _fail "a.txt not fused with C0 (wt mod + last commit)"; }
grep -q '^eq  b.txt .*C1 add b'          "$WORK/out" || { cat "$WORK/out" >&2; _fail "b.txt not fused with C1"; }
grep -q '^dir sub/ .*C2 edit sub'        "$WORK/out" || { cat "$WORK/out" >&2; _fail "sub/ not fused with the newest-under commit C2"; }

echo "PASS [$NAME]"
