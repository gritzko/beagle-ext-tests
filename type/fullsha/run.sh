#!/bin/sh
# test/type/fullsha — JS-082: `jab type:#<40hex>` must resolve a FULL 40-char
# object id, not just a short prefix.  The bug: the view gated the hex then handed
# it to store.resolveHexAny, whose {1,39} prefix scanner returns undefined for a
# 40-char string → TYPENONE even though the header promises full-sha support.
#
# Oracle: C `be type:` is a STUB (PROJNONE, "not implemented"), so there is no C
# stdout to diff — the oracle is jab's OWN short-prefix path (already correct).
# The fix's contract: full-sha resolves to the SAME type the short prefix does,
# in EVERY slot form (`#<hex>`, `?#<hex>`, `?<hex>`), for blob/tree/commit.
# RED pre-fix (full-sha → empty/nonzero), GREEN after.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/type/fullsha
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "type: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "type: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "type: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/type/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# A worktree with one committed file → a commit, its tree, and a blob.
WT="$WORK/wt"; mkdir -p "$WT/.be"
( cd "$WT" && printf 'hello world\n' > a.txt && "$BE" post 'first commit' >/dev/null 2>&1 ) \
    || _fail "could not seed the commit"

# The commit, tree and blob full shas (the 40-hex tokens of the `tree:` row).
COMMIT=$("$JABC" "$_ROOT/put/tipsha.js" "$WT")
[ -n "$COMMIT" ] || _fail "could not resolve the trunk tip sha"
case "$COMMIT" in *[!0-9a-f]*|"") _fail "commit sha not 40-hex: '$COMMIT'" ;; esac
TREE=$( cd "$WT" && "$JABC" commit "commit:#$COMMIT" 2>/dev/null \
        | awk '$1=="tree"{print $2;exit}' )
case "$TREE" in *[!0-9a-f]*|"") _fail "tree sha not 40-hex: '$TREE'" ;; esac
BLOB=$( cd "$WT" && "$JABC" tree "tree:#$COMMIT" 2>/dev/null \
        | awk '/[^a-f]a.txt$|^a.txt$|\ta.txt$/{for(i=1;i<=NF;i++) if($i~/^[0-9a-f]{40}$/){print $i;exit}}' )
case "$BLOB" in *[!0-9a-f]*|"") _fail "blob sha not 40-hex: '$BLOB'" ;; esac

# parity <label> <full> <short> <want> — jab full-sha == jab short == <want>.
parity() {
    _lbl="$1"; _full="$2"; _short="$3"; _want="$4"
    ( cd "$WT" && "$JABC" type "type:$_short" ) >"$WORK/short.$_lbl" 2>/dev/null \
        || _fail "[$_lbl] jab type:'$_short' (short oracle) failed"
    ( cd "$WT" && "$JABC" type "type:$_full" ) >"$WORK/full.$_lbl" 2>"$WORK/err.$_lbl" \
        || _fail "[$_lbl] jab type:'$_full' (full sha) failed (RED: $(cat "$WORK/err.$_lbl"))"
    [ -s "$WORK/full.$_lbl" ] || _fail "[$_lbl] full-sha emitted ZERO bytes (RED)"
    cmp -s "$WORK/short.$_lbl" "$WORK/full.$_lbl" \
        || _fail "[$_lbl] full-sha type != short-prefix type"
    grep -q "^$_want\$" "$WORK/full.$_lbl" \
        || _fail "[$_lbl] full-sha type != $_want ($(cat "$WORK/full.$_lbl"))"
}

# Every object kind, every slot form (short = first 8 hex).
parity blob-frag   "#$BLOB"          "#$(printf '%s' "$BLOB" | cut -c1-8)"   blob
parity blob-qfrag  "?#$BLOB"         "?#$(printf '%s' "$BLOB" | cut -c1-8)"  blob
parity blob-query  "?$BLOB"          "?$(printf '%s' "$BLOB" | cut -c1-8)"   blob
parity tree-frag   "#$TREE"          "#$(printf '%s' "$TREE" | cut -c1-8)"   tree
parity commit-frag "#$COMMIT"        "#$(printf '%s' "$COMMIT" | cut -c1-8)" commit

# Negative: a non-existent full sha must FAIL cleanly (no stdout, nonzero).
ZERO=0000000000000000000000000000000000000000
( cd "$WT" && "$JABC" type "type:#$ZERO" ) >"$WORK/zero" 2>/dev/null \
    && _fail "[neg] jab type:#<zero-sha> SUCCEEDED (should fail)"
[ -s "$WORK/zero" ] && _fail "[neg] jab type:#<zero-sha> emitted bytes"

echo "PASS [$NAME]"
