#!/bin/sh
# test/blob/fullsha — JS-082: `jab blob:#<40hex>` must resolve a FULL 40-char
# object id, not just a short prefix.  The bug: the view gated the hex then handed
# it to store.resolveHexAny, whose {1,39} prefix scanner returns undefined for a
# 40-char string → BLOBNONE even though the header promises full-sha support.
# Both the bare-object AND the path-bearing root-tree slots are exercised.
#
# Oracle: C `be blob:` always KEEPFAILs (it emits a banner-less raw dump; the JS
# view emits a `blob <sha>#L<n>` HUNK — INTENDED divergence, per blob.js's header).
# So the oracle is jab's OWN short-prefix path (already correct).  The fix's
# contract: full-sha emits the SAME bytes the short prefix does, in EVERY slot
# form (`#<hex>`, `?#<hex>`, `?<hex>`, and `<path>?#<hex>`).  RED pre-fix
# (full-sha → empty/nonzero), GREEN after.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/blob/fullsha
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (it LAGS jab); locate jab and
# alias BE=$JABC so legacy `"$BE" post/put` seeds run jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "blob: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "blob: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "blob: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/blob/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# A worktree with one committed file → a commit, its tree, and a blob.
WT="$WORK/wt"; mkdir -p "$WT/.be"
( cd "$WT" && printf 'hello world\n' > a.txt && "$BE" post 'first commit' >/dev/null 2>&1 ) \
    || _fail "could not seed the commit"

# The commit + the blob full shas.
COMMIT=$("$JABC" "$_ROOT/put/tipsha.js" "$WT")
[ -n "$COMMIT" ] || _fail "could not resolve the trunk tip sha"
case "$COMMIT" in *[!0-9a-f]*|"") _fail "commit sha not 40-hex: '$COMMIT'" ;; esac
BLOB=$( cd "$WT" && "$JABC" tree "tree:#$COMMIT" 2>/dev/null \
        | awk '/[^a-f]a.txt$|^a.txt$|\ta.txt$/{for(i=1;i<=NF;i++) if($i~/^[0-9a-f]{40}$/){print $i;exit}}' )
case "$BLOB" in *[!0-9a-f]*|"") _fail "blob sha not 40-hex: '$BLOB'" ;; esac
SHORT=$(printf '%s' "$BLOB" | cut -c1-8)
CSHORT=$(printf '%s' "$COMMIT" | cut -c1-8)

# parity <label> <full> <short> — jab full-sha bytes == jab short-prefix bytes.
# (The bare-object banner is the RESOLVED full sha for BOTH, so the bytes match.)
parity() {
    _lbl="$1"; _full="$2"; _short="$3"
    ( cd "$WT" && "$JABC" blob "blob:$_short" ) >"$WORK/short.$_lbl" 2>/dev/null \
        || _fail "[$_lbl] jab blob:'$_short' (short oracle) failed"
    [ -s "$WORK/short.$_lbl" ] || _fail "[$_lbl] short oracle emitted ZERO bytes"
    ( cd "$WT" && "$JABC" blob "blob:$_full" ) >"$WORK/full.$_lbl" 2>"$WORK/err.$_lbl" \
        || _fail "[$_lbl] jab blob:'$_full' (full sha) failed (RED: $(cat "$WORK/err.$_lbl"))"
    [ -s "$WORK/full.$_lbl" ] || _fail "[$_lbl] full-sha emitted ZERO bytes (RED)"
    cmp -s "$WORK/short.$_lbl" "$WORK/full.$_lbl" \
        || _fail "[$_lbl] full-sha bytes != short-prefix bytes"
    grep -q 'hello world' "$WORK/full.$_lbl" || _fail "[$_lbl] missing blob content"
}

# Bare-object forms (the `resolveHexAny` bare path).
parity frag    "#$BLOB"   "#$SHORT"
parity qfrag   "?#$BLOB"  "?#$SHORT"
parity query   "?$BLOB"   "?$SHORT"

# Path-bearing root-tree form (the `resolveRootTree` path): the blob at a.txt in
# the tree of a FULL commit sha must equal the same under a short commit sha.
parity path-q  "a.txt?$COMMIT"   "a.txt?$CSHORT"
parity path-qf "a.txt?#$COMMIT"  "a.txt?#$CSHORT"

# Negative: a non-existent full sha must FAIL cleanly (no stdout, nonzero); a full
# COMMIT sha is not a blob → must FAIL (BLOBFAIL), not emit the commit object.
ZERO=0000000000000000000000000000000000000000
( cd "$WT" && "$JABC" blob "blob:#$ZERO" ) >"$WORK/zero" 2>/dev/null \
    && _fail "[neg] jab blob:#<zero-sha> SUCCEEDED (should fail)"
[ -s "$WORK/zero" ] && _fail "[neg] jab blob:#<zero-sha> emitted bytes"
( cd "$WT" && "$JABC" blob "blob:#$COMMIT" ) >"$WORK/notblob" 2>/dev/null \
    && _fail "[neg] jab blob:#<full-commit> SUCCEEDED (commit is not a blob)"
[ -s "$WORK/notblob" ] && _fail "[neg] jab blob:#<full-commit> emitted bytes"

echo "PASS [$NAME]"
