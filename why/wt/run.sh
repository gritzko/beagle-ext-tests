#!/bin/sh
# WHY-001 test/why/wt — `why:<path>` (no query) blames the WORKING TREE, so it
# ACCOUNTS FOR UNCOMMITTED changes (diff:'s wt-vs-base twin): committed tokens keep
# their commit hue, uncommitted (edited / wholly-new) tokens render PLAIN.  Covers
# (a) an edited committed file — the uncommitted lines SHOW and stay plain while a
# committed line keeps its wash; (b) a WHOLLY-NEW uncommitted file — content shows
# (was `no hunks`), all plain.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/why/wt
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (it LAGS jab); locate jab and
# alias BE=$JABC so legacy `"$BE" post/put` seeds run jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "why/wt: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "why/wt: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "why/wt: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/why/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# WHY-001: pin commit time for a stable committed sha (hue determinism).
: "${SOURCE_DATE_EPOCH:=1467331200}"; export SOURCE_DATE_EPOCH

WT="$WORK/wt"; mkdir -p "$WT/.be"
cd "$WT"
# c1 commits f.txt (alpha/beta).  Then edit it ON DISK without committing, and add
# a wholly-new g.txt — both UNCOMMITTED (the wt state `why:` must now reflect).
printf 'alpha\nbeta\n' > f.txt
"$BE" post 'c1 seed' >/dev/null 2>&1 || _fail "post c1"
printf 'alpha\nBETA\ngamma\n' > f.txt            # uncommitted edit (no put/post)
printf 'newfile line\n' > g.txt                  # wholly-new uncommitted file

# 1. edited committed file: the wt content shows (BETA + gamma present) AND the
#    committed `alpha` still shows — blame reflects the working tree, not c1's tree.
( cd "$WT" && "$JABC" why "why:f.txt" --plain ) >"$WORK/fplain" 2>"$WORK/ferr" \
    || _fail "why:f.txt --plain failed ($(cat "$WORK/ferr"))"
grep -q '^alpha$' "$WORK/fplain" || _fail "committed line 'alpha' missing"
grep -q '^BETA$'  "$WORK/fplain" || _fail "uncommitted edit 'BETA' missing (wt not blamed)"
grep -q '^gamma$' "$WORK/fplain" || _fail "uncommitted add 'gamma' missing (wt not blamed)"

# 2. --color: the committed `alpha` carries a bg wash; the uncommitted `gamma` is
#    PLAIN (no bg) — the whole point of "account for uncommitted changes".
( cd "$WT" && "$JABC" why "why:f.txt" --color ) >"$WORK/fcolor" 2>/dev/null \
    || _fail "why:f.txt --color failed"
grep -a 'alpha' "$WORK/fcolor" | grep -qaE '48;2;[0-9]+;[0-9]+;[0-9]+' \
    || _fail "committed 'alpha' got no commit bg wash"
grep -a 'gamma' "$WORK/fcolor" | grep -qaE '48;2;[0-9]+;[0-9]+;[0-9]+' \
    && _fail "uncommitted 'gamma' was washed — must render PLAIN"

# 3. wholly-new uncommitted file: content SHOWS (not `no hunks`) and is all-plain.
( cd "$WT" && "$JABC" why "why:g.txt" --plain ) >"$WORK/gplain" 2>/dev/null \
    || _fail "why:g.txt --plain failed"
[ -s "$WORK/gplain" ] || _fail "why:g.txt emitted ZERO bytes (regressed to 'no hunks')"
grep -q 'newfile line' "$WORK/gplain" || _fail "new-file content missing from why:g.txt"
( cd "$WT" && "$JABC" why "why:g.txt" --color ) >"$WORK/gcolor" 2>/dev/null \
    || _fail "why:g.txt --color failed"
_gbg=$(tail -n +2 "$WORK/gcolor" | grep -oaE '48;2;[0-9]+;[0-9]+;[0-9]+' | sort -u | wc -l | tr -d ' ')
[ "$_gbg" -eq 0 ] || _fail "wholly-new file must be all-plain, got $_gbg bg hue(s)"

echo "PASS [$NAME]"
