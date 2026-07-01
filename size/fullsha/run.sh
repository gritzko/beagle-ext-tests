#!/bin/sh
# test/size/fullsha — JS-082: `jab size:#<40hex>` must resolve a FULL 40-char
# object id, not just a short prefix.  The bug: the view gated the hex then handed
# it to store.resolveHexAny, whose {1,39} prefix scanner returns undefined for a
# 40-char string → SIZENONE even though the header promises full-sha support.
#
# Oracle: C `be size:` is a STUB (PROJNONE, "not implemented"), so there is no C
# stdout to diff — the oracle is jab's OWN short-prefix path (already correct).
# The fix's contract: full-sha resolves to the SAME size the short prefix does,
# in EVERY slot form C accepts (`#<hex>`, `?#<hex>`, `?<hex>`).  RED pre-fix
# (full-sha → empty/nonzero), GREEN after.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/size/fullsha
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "size: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "size: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "size: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/size/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink so bareword `jab size`
# resolves the extension via jab's upward be/-scan from the worktree cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# A worktree with one committed file → a commit, its tree, and a blob.
WT="$WORK/wt"; mkdir -p "$WT/.be"
( cd "$WT" && printf 'hello world\n' > a.txt && "$BE" post 'first commit' >/dev/null 2>&1 ) \
    || _fail "could not seed the commit"

# The trunk tip (commit) full sha + the blob sha of a.txt (the 40-hex token in
# the `tree:` row, robust to column layout).
COMMIT=$("$JABC" "$_ROOT/put/tipsha.js" "$WT")
[ -n "$COMMIT" ] || _fail "could not resolve the trunk tip sha"
case "$COMMIT" in *[!0-9a-f]*|"") _fail "commit sha not 40-hex: '$COMMIT'" ;; esac
BLOB=$( cd "$WT" && "$JABC" tree "tree:#$COMMIT" 2>/dev/null \
        | awk '/[^a-f]a.txt$|^a.txt$|\ta.txt$/{for(i=1;i<=NF;i++) if($i~/^[0-9a-f]{40}$/){print $i;exit}}' )
case "$BLOB" in *[!0-9a-f]*|"") _fail "blob sha not 40-hex: '$BLOB'" ;; esac
SHORT=$(printf '%s' "$BLOB" | cut -c1-8)

# parity <label> <full-form> <short-form> — jab full-sha == jab short-prefix.
parity() {
    _lbl="$1"; _full="$2"; _short="$3"
    ( cd "$WT" && "$JABC" size "size:$_short" ) >"$WORK/short.$_lbl" 2>/dev/null \
        || _fail "[$_lbl] jab size:'$_short' (short oracle) failed"
    [ -s "$WORK/short.$_lbl" ] || _fail "[$_lbl] short oracle emitted ZERO bytes"
    ( cd "$WT" && "$JABC" size "size:$_full" ) >"$WORK/full.$_lbl" 2>"$WORK/err.$_lbl" \
        || _fail "[$_lbl] jab size:'$_full' (full sha) failed (RED: $(cat "$WORK/err.$_lbl"))"
    [ -s "$WORK/full.$_lbl" ] || _fail "[$_lbl] full-sha emitted ZERO bytes (RED)"
    #  JAB-003: drop the hunk `<scheme>:` banner (embeds the query sha — differs
    #  full vs short) so the BODY (the size) compares.
    sed -E '/^[a-z][a-z0-9]*:/d' "$WORK/short.$_lbl" >"$WORK/short.$_lbl.n"
    sed -E '/^[a-z][a-z0-9]*:/d' "$WORK/full.$_lbl"  >"$WORK/full.$_lbl.n"
    cmp -s "$WORK/short.$_lbl.n" "$WORK/full.$_lbl.n" \
        || _fail "[$_lbl] full-sha size != short-prefix size"
}

parity frag    "#$BLOB"    "#$SHORT"
parity qfrag   "?#$BLOB"   "?#$SHORT"
parity query   "?$BLOB"    "?$SHORT"

# The blob's known size is 12 ("hello world\n").
grep -q '^12$' "$WORK/full.frag" || _fail "blob size != 12 ($(cat "$WORK/full.frag"))"

# A full COMMIT sha resolves to the commit object's size (no deref, like short).
( cd "$WT" && "$JABC" size "size:#$COMMIT" ) >"$WORK/csize" 2>/dev/null \
    || _fail "[commit] jab size:#<full-commit> failed"
[ -s "$WORK/csize" ] || _fail "[commit] full-commit size emitted ZERO bytes"

# Negative: a non-existent full sha must FAIL cleanly (no stdout, nonzero).
ZERO=0000000000000000000000000000000000000000
( cd "$WT" && "$JABC" size "size:#$ZERO" ) >"$WORK/zero" 2>/dev/null \
    && _fail "[neg] jab size:#<zero-sha> SUCCEEDED (should fail)"
[ -s "$WORK/zero" ] && _fail "[neg] jab size:#<zero-sha> emitted bytes"

echo "PASS [$NAME]"
