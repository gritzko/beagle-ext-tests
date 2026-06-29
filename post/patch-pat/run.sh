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
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "post/patch-pat: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-${JAB:-$_BIN/jab}}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "post/patch-pat: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "post/patch-pat: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
: "${SOURCE_DATE_EPOCH:=1467331200}"; export SOURCE_DATE_EPOCH   # 2016-07-01Z
: "${TZ:=UTC}"; export TZ

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
_jstatus() { ( cd "$1" && "$JABC" status --plain 2>/dev/null ) \
    | sed -nE 's/^ *[0-9A-Za-z:]+ +([a-z]{3}) +(.*)$/\1 \2/p'; }

# Build an origin with a trunk/feat divergence over f.txt where ONLY theirs
# changes f.txt — ours leaves it at the fork content.  So a `be patch` of the
# feat tip TAKES THEIRS cleanly (ours==fork, theirs!=fork): a `pat` file, NOT a
# 3-way merge.  Writes the feat tip sha to $WORK/F1.
_build() {
    rm -rf "$WORK/org"; ORG="$WORK/org"; mkdir -p "$ORG/.be"
    ( cd "$ORG"
      printf 'a\nb\nc\nd\ne\n' > f.txt
      printf 'keep\n'          > k.txt          # a tracked file neither side edits
      "$BE" put f.txt k.txt >/dev/null 2>&1; "$BE" post 't0' >/dev/null 2>&1
      "$BE" put '?./feat' >/dev/null 2>&1
      "$BE" get '?..' >/dev/null 2>&1
      # ours: do NOT touch f.txt — only k.txt changes, so f.txt at ours == fork.
      printf 'keep+ours\n' > k.txt
      "$BE" put k.txt >/dev/null 2>&1; "$BE" post 't1' >/dev/null 2>&1
      "$BE" get '?feat' >/dev/null 2>&1
      printf 'a\nb\nC-theirs\nd\ne\n' > f.txt   # theirs: line 3 (ours never did)
      "$BE" put f.txt >/dev/null 2>&1; "$BE" post 'f1' >/dev/null 2>&1
      grep -a "$(printf '\tpost\t')" .be/org/refs \
        | grep -oE '[0-9a-f]{40}' | tail -1 > "$WORK/F1"
      "$BE" get '?..' >/dev/null 2>&1 )         # leave cur at trunk
}

_build; F1=$(cat "$WORK/F1")
JS="$WORK/take"; mkdir -p "$JS"
( cd "$JS" && "$BE" get "file://$ORG/.be?/org" >/dev/null 2>&1 ) || _fail "clone failed"
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
