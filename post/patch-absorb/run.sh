#!/bin/sh
# test/post/patch-absorb — DIS-057 (subsumes POST-005): `post` CONSUMES an
# in-scope `patch` row's theirs tree.  Before DIS-057 a `patch` row in scope
# threw POSTSCOPE; now the unified classifier reads each patch-derived file as
# pat/mrg/cnf (via the patch verb's mtime stamp OFFSET) and `post` commits the
# merged content — a clean/merged absorb commits, a conflict (`cnf`) refuses
# POSTCFLCT until `--force`.  JS-ONLY: the patch verb's stamp offset + the
# subsumed throw diverge from native, so this asserts JS behavior end to end.
#
# RED before DIS-057: `jab post` on a patched tree throws POSTSCOPE.  GREEN
# after: a merged absorb commits; a conflicted one refuses, then --force commits.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/patch-absorb
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (LAGS jab); alias BE=$JABC so the
# legacy `"$BE"` seeds run jab.
JABC=${JABC:-${JAB:-${BIN:+$BIN/jab}}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/patch-absorb: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC"); BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "post/patch-absorb: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
# Pin the clock so the builder shas (and the `patch ?<sha>` row uri) are stable.
: "${SOURCE_DATE_EPOCH:=1467331200}"; export SOURCE_DATE_EPOCH   # 2016-07-01Z
: "${TZ:=UTC}"; export TZ

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
_jstatus() { ( cd "$1" && "$JABC" status --plain 2>/dev/null ) \
    | sed -nE 's/^ *[0-9A-Za-z:]+ +([a-z]{3}) +(.*)$/\1 \2/p'; }

# TEST-003 jab-only DAG.  The store's rolling keeper.idx indexes only the LATEST
# keeper, so t0's object (the fork point) reads MISSING after a 2nd post; drop the
# stale idx before each op.  Bootstrap post-alone, absolute `?feat`, and switch
# back to trunk by PINNING the saved t0 (bare `?` folds to the current branch).
_jab() { rm -f "$ORG"/.be/*.keeper.idx 2>/dev/null; "$BE" "$@"; }
_build() {   # _build OURS_LINE THEIRS_LINE
    rm -rf "$WORK/org"; ORG="$WORK/org"; mkdir -p "$ORG/.be"
    ( cd "$ORG"
      printf 'a\nb\nc\nd\ne\n' > f.txt
      _jab post 't0' >/dev/null 2>&1
      T0=$(grep -a "$(printf '\tpost\t')" .be/refs | grep -oE '[0-9a-f]{40}' | head -1)
      _jab put '?feat' >/dev/null 2>&1
      _jab get '?feat' >/dev/null 2>&1
      printf 'a\nb\nc\n%s\ne\n' "$2" > f.txt          # theirs: line 4
      _jab put f.txt >/dev/null 2>&1; _jab post 'f1' >/dev/null 2>&1
      grep -a "$(printf '\tpost\t')" .be/refs \
        | grep -aE '\?feat#' | grep -oE '[0-9a-f]{40}' | tail -1 > "$WORK/F1"
      _jab get "?#$T0" >/dev/null 2>&1               # back to trunk @ t0
      printf 'a\n%s\nc\nd\ne\n' "$1" > f.txt          # ours: line 2
      _jab put f.txt >/dev/null 2>&1; _jab post 't1' >/dev/null 2>&1
      rm -f "$ORG"/.be/*.keeper.idx )                 # let the clone see every commit
}

# ===== leg 1: a clean MERGE absorb commits =====
# ours edits line 2, theirs line 4 (disjoint) → a clean 3-way merge → `mrg`.
_build B D; F1=$(cat "$WORK/F1")
JS="$WORK/merge"; mkdir -p "$JS"
( cd "$JS" && "$BE" get "file://$ORG/.be" >/dev/null 2>&1 ) || _fail "clone failed (merge)"
( cd "$JS" && "$JABC" patch "#$F1" >/dev/null 2>&1 ) || _fail "patch failed (merge)"
st=$(_jstatus "$JS")
[ "$st" = "mrg f.txt" ] || _fail "merge-absorb status != 'mrg f.txt':
$st"
echo "ok: a patch-merged file reads 'mrg' (stamp offset)"
( cd "$JS" && "$JABC" post 'absorb feat (merge)' ) >"$WORK/m.out" 2>"$WORK/m.err" \
    || _fail "post of a merged absorb FAILED (POSTSCOPE not subsumed?): $(cat "$WORK/m.err")"
grep -qE '(^|[[:space:]])mod f.txt$' "$WORK/m.out" \
    || _fail "merged absorb did not commit f.txt:
$(cat "$WORK/m.out")"
[ -z "$(_jstatus "$JS")" ] || _fail "wt not clean after absorbing the merge:
$(_jstatus "$JS")"
echo "ok: post CONSUMES a patch-merged tree (commits, then clean) — POST-005 subsumed"

# The absorb is a REAL MERGE commit: parents = ours-tip + theirs (the patch row's
# theirs commit).  base=ours (DIS-057 RULING) did NOT change this — the merged
# bytes ride the tree, theirs rides the second parent.  Assert F1 (the feat tip)
# is among the absorb commit's parents AND there are exactly TWO parents.
pars=$( cd "$JS" && BEDIR="$BEDIR" "$JABC" "$_CASE/assert_parents.js" 2>/dev/null )
np=$(printf '%s\n' "$pars" | grep -cE '^[0-9a-f]{40}$')
[ "$np" = "2" ] || _fail "absorb is not a 2-parent merge commit (parents: $pars)"
printf '%s\n' "$pars" | grep -qx "$F1" \
    || _fail "absorb commit does not record theirs ($F1) as a merge parent:
$pars"
echo "ok: the absorb is a MERGE commit (parents = ours-tip + theirs)"

# ===== leg 2: a CONFLICT absorb refuses, then --force commits =====
# ours + theirs both edit line 2 differently → a true conflict → `cnf` + markers.
# (theirs edits line 2 here, not line 4, so it overlaps ours.)
_build2() {   # TEST-003 jab-only DAG (see _build note)
    rm -rf "$WORK/org"; ORG="$WORK/org"; mkdir -p "$ORG/.be"
    ( cd "$ORG"
      printf 'a\nb\nc\nd\ne\n' > f.txt
      _jab post 't0' >/dev/null 2>&1
      T0=$(grep -a "$(printf '\tpost\t')" .be/refs | grep -oE '[0-9a-f]{40}' | head -1)
      _jab put '?feat' >/dev/null 2>&1
      _jab get '?feat' >/dev/null 2>&1
      printf 'a\nX\nc\nd\ne\n' > f.txt                # theirs: line 2 = X (conflicts)
      _jab put f.txt >/dev/null 2>&1; _jab post 'f1' >/dev/null 2>&1
      grep -a "$(printf '\tpost\t')" .be/refs \
        | grep -aE '\?feat#' | grep -oE '[0-9a-f]{40}' | tail -1 > "$WORK/F1"
      _jab get "?#$T0" >/dev/null 2>&1               # back to trunk @ t0
      printf 'a\nY\nc\nd\ne\n' > f.txt                # ours: line 2 = Y
      _jab put f.txt >/dev/null 2>&1; _jab post 't1' >/dev/null 2>&1
      rm -f "$ORG"/.be/*.keeper.idx )
}
_build2; F1=$(cat "$WORK/F1")
JS="$WORK/conf"; mkdir -p "$JS"
( cd "$JS" && "$BE" get "file://$ORG/.be" >/dev/null 2>&1 ) || _fail "clone failed (conf)"
( cd "$JS" && "$JABC" patch "#$F1" >/dev/null 2>&1 ) || _fail "patch failed (conf)"
st=$(_jstatus "$JS")
[ "$st" = "cnf f.txt" ] || _fail "conflict-absorb status != 'cnf f.txt':
$st"
echo "ok: a patch-conflicted file reads 'cnf' (stamp offset + conf→cnf)"
if ( cd "$JS" && "$JABC" post 'absorb feat (conf)' ) >"$WORK/c.out" 2>"$WORK/c.err"; then
    _fail "post of a conflicted absorb should REFUSE (POSTCFLCT):
$(cat "$WORK/c.out")"
fi
grep -q POSTCFLCT "$WORK/c.err" \
    || _fail "expected POSTCFLCT on a conflict-marked file, got:
$(cat "$WORK/c.err")"
echo "ok: post REFUSES a conflict-marked (cnf) absorb (POSTCFLCT)"
( cd "$JS" && "$JABC" post --force 'absorb feat (forced)' ) >"$WORK/cf.out" 2>"$WORK/cf.err" \
    || _fail "post --force of a conflict FAILED: $(cat "$WORK/cf.err")"
grep -qE '(^|[[:space:]])mod f.txt$' "$WORK/cf.out" \
    || _fail "forced conflict absorb did not commit f.txt:
$(cat "$WORK/cf.out")"
echo "ok: post --force commits the conflict-marked absorb"

echo "PASS [$NAME]"
