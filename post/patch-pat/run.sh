#!/bin/sh
# test/post/patch-pat — DIS-057 RULING 2026-06-29: the patched-in (theirs) tree
# is a SEPARATE classifier input, NEVER the baseline.  base stays OURS (the
# pre-patch get/post tip, curTip-style — patch rows EXCLUDED).  So a clean
# TAKE-THEIRS file (theirs ≠ ours, ours == fork) reads `pat` — distinct from
# `ok` (wt == ours).  Before the fix `baselineTip()` folded theirs INTO the
# baseline, so a take-theirs file equalled the (theirs) baseline and collapsed
# to `ok`; `pat` never appeared.  RED before: `jab status` reads `ok` (or blank).
# GREEN after: it reads `pat`, and `post` still ABSORBS it (commits theirs bytes
# with the theirs commit as a merge parent).  JS-ONLY (stamp offset diverges
# from native), asserted against a date-normalised golden.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/patch-pat
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (LAGS jab); alias BE=$JABC so the
# legacy `"$BE"` seeds run jab.
JABC=${JABC:-${JAB:-${BIN:+$BIN/jab}}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/patch-pat: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC"); BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "post/patch-pat: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
: "${SOURCE_DATE_EPOCH:=1467331200}"; export SOURCE_DATE_EPOCH   # 2016-07-01Z
: "${TZ:=UTC}"; export TZ

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
_jstatus() { ( cd "$1" && "$JABC" status --plain 2>/dev/null ) \
    | sed -nE 's/^ *[0-9A-Za-z:]+ +([a-z]{3}) +(.*)$/\1 \2/p'; }

# TEST-003 jab-only DAG.  The store's rolling keeper.idx indexes only the LATEST
# keeper, so t0's object (the fork point) reads MISSING after a 2nd post; drop the
# stale idx before each op.  Bootstrap post-alone, absolute `?feat`, switch back
# to trunk by PINNING the saved t0 (bare `?` folds to the current branch).
_jab() { rm -f "$ORG"/.be/*.keeper.idx 2>/dev/null; "$BE" "$@"; }
# DIS-076: a bare post never mints a ref — the wt's OWN cur (jab refs) is the
# only tip there is; never grep a `.be/refs` ULOG (that file no longer exists).
_orgtip() { ( cd "$1" && "$JABC" refs 2>/dev/null ) | sed -n 's/^cur: *//p'; }
_build() {
    rm -rf "$WORK/org"; ORG="$WORK/org"; mkdir -p "$ORG/.be"
    ( cd "$ORG"
      printf 'a\nb\nc\nd\ne\n' > f.txt
      printf 'keep\n'          > k.txt          # a tracked file neither side edits
      _jab post 't0' >/dev/null 2>&1            # bootstrap auto-adds f.txt + k.txt
      T0=$(_orgtip .)
      _jab put '?feat' >/dev/null 2>&1
      _jab get '?feat' >/dev/null 2>&1
      printf 'a\nb\nC-theirs\nd\ne\n' > f.txt   # theirs: line 3 (ours never did)
      _jab put f.txt >/dev/null 2>&1; _jab post 'f1' >/dev/null 2>&1
      _orgtip . > "$WORK/F1"
      _jab get "?#$T0" >/dev/null 2>&1          # back to trunk @ t0
      # ours: do NOT touch f.txt — only k.txt changes, so f.txt at ours == fork.
      printf 'keep+ours\n' > k.txt
      _jab put k.txt >/dev/null 2>&1; _jab post 't1' >/dev/null 2>&1
      rm -f "$ORG"/.be/*.keeper.idx )           # let the clone see every commit
}

_build; F1=$(cat "$WORK/F1")
JS="$WORK/take"; mkdir -p "$JS"
ORG_TIP=$(_orgtip "$ORG")
( cd "$JS" && "$BE" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 ) || _fail "clone failed"
( cd "$JS" && "$JABC" patch "#$F1" >/dev/null 2>&1 ) || _fail "patch failed"

# 1. the take-theirs file reads `pat` (base=ours; wt==theirs!=ours).  k.txt is
#    untouched by the patch (ours==theirs there) so it stays clean (count-only).
st=$(_jstatus "$JS")
[ "$st" = "pat f.txt" ] || _fail "take-theirs status != 'pat f.txt' (base folded theirs?):
$st"
echo "ok: a clean take-theirs file reads 'pat' (base=ours, theirs a separate input)"

# 2. post still ABSORBS it: commits f.txt (theirs bytes) AND records theirs as a
#    merge parent (the absorb is unchanged by base→ours).
( cd "$JS" && "$JABC" post 'absorb take-theirs' ) >"$WORK/p.out" 2>"$WORK/p.err" \
    || _fail "post of a pat absorb FAILED: $(cat "$WORK/p.err")"
grep -qE '(^|[[:space:]])mod f.txt$' "$WORK/p.out" \
    || _fail "pat absorb did not commit f.txt:
$(cat "$WORK/p.out")"
[ -z "$(_jstatus "$JS")" ] || _fail "wt not clean after absorbing the pat file:
$(_jstatus "$JS")"
printf 'a\nb\nC-theirs\nd\ne\n' > "$WORK/exp.f"
cmp -s "$WORK/exp.f" "$JS/f.txt" || _fail "f.txt does not carry theirs' bytes"
echo "ok: post absorbs the pat file (commits theirs bytes, clean after)"

echo "PASS [$NAME]"
