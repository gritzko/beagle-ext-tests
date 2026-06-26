#!/bin/sh
# test/commit/links — BRO-006: `be/views/commit/commit.js` must emit `U` click-
# targets so a bro pager left-click on a commit's `tree`/`parent` sha navigates,
# mirroring C keeper KEEPProjCommit (keeper/PROJ.c:468-493): `tree <sha>` →
# `tree:?<sha40>`, `parent <sha>` → `commit:?<sha40>` (open the parent).  The
# synthetic `commit <sha>` header is the page itself and carries NO `U`.
#
# The pager consumes U targets from the HUNK tok32 stream (views/bro/pager.js
# `_uriAt`: a visible token followed by a `U` token whose hidden text bytes ARE
# the URI).  `jab commit:?<sha> --tlv` IS that on-wire stream, so we capture it,
# load it via the pager's own hunksFromTlv, and assert the tree/parent U targets.
# RED before the fix (commit emits colour spans but NO `U` token → zero U
# targets); GREEN after.  Also asserts COMMIT-003/004/005: PLAIN output stays
# byte-identical to native metadata (the U bytes stay hidden), no `:?` leak.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/commit/links
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "commit/links: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-${JAB:-$_BIN/jab}}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "commit/links: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "commit/links: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/commit/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink so bareword `jab commit`
# resolves the extension via jab's upward be/-scan from the worktree cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sf "$BEDIR" "$TMP/$$/be" 2>/dev/null || true

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# A 2-commit chain so the tip commit HAS a parent (the `parent` header is the
# point of the test).  `post` auto-stages the first commit; a new file after
# needs an explicit `put` before it can be posted.
WT="$WORK/wt"; mkdir -p "$WT/.be"
cd "$WT"
printf 'one\n' > a.txt;                       "$BE" post 'first commit'  >/dev/null 2>&1 || _fail "post 1"
printf 'two\n' > b.txt; "$BE" put b.txt >/dev/null 2>&1; "$BE" post 'second commit' >/dev/null 2>&1 || _fail "post 2"

# The tip commit's full 40-hex sha (resolvable; HAS a parent).
SHA=$("$JABC" "$_ROOT/put/tipsha.js" "$WT")
[ -n "$SHA" ] || _fail "could not resolve the tip sha"
case "$SHA" in *[!0-9a-f]*|"") _fail "tip sha not 40-hex: '$SHA'" ;; esac

# 1. PLAIN parity: capture jab + native metadata.  jab's standalone view emits
#    ONLY the keeper metadata (COMMIT-002's inline-diff relay is the dispatcher's
#    job, absent from `jab commit:`); native plain continues into the diff.  So
#    jab plain == native's metadata prefix, plus the ONE trailing blank-line
#    separator the JS HUNK content render appends (a binding-level constant).
( cd "$WT" && "$JABC" commit "commit:?$SHA" --plain ) >"$WORK/jab.plain" 2>"$WORK/jab.err" \
    || _fail "jab commit --plain failed ($(cat "$WORK/jab.err"))"
( cd "$WT" && "$BE"   commit "commit:?$SHA" --plain ) >"$WORK/nat.plain" 2>/dev/null \
    || _fail "native be commit --plain failed"
[ -s "$WORK/jab.plain" ] || _fail "jab commit --plain emitted ZERO bytes"
# The U URI bytes must NEVER leak into the visible plain text.
grep -q ':?' "$WORK/jab.plain" && _fail "U URI bytes leaked into --plain output"
# jab metadata sans its trailing separator must be a byte-exact prefix of native.
_n=$(wc -c <"$WORK/jab.plain"); _m=$((_n - 1))
head -c "$_m" "$WORK/jab.plain" >"$WORK/jab.meta"
head -c "$_m" "$WORK/nat.plain" >"$WORK/nat.meta"
cmp -s "$WORK/jab.meta" "$WORK/nat.meta" \
    || { echo "--- jab ---"; cat -A "$WORK/jab.plain"
         echo "--- native ---"; cat -A "$WORK/nat.plain"
         _fail "jab plain not byte-identical to native metadata (U must stay hidden)"; }
echo "ok: jab commit --plain byte-matches native metadata (U bytes hidden)"

# Extract the tip commit's tree + parent shas (the U-target operands) from the
# plain headers; build the expected `tree:?<sha>` / `commit:?<sha>` U targets.
TREE=$(awk '$1=="tree"{print $2; exit}'   "$WORK/jab.plain")
PARENT=$(awk '$1=="parent"{print $2; exit}' "$WORK/jab.plain")
[ -n "$TREE" ]   || _fail "no tree header in commit metadata"
[ -n "$PARENT" ] || _fail "no parent header (2-commit chain expected)"

# 2. U click-targets: capture the on-wire HUNK stream (--tlv) and assert the
#    tree/parent rows carry a `U` token decoding (via the pager `_uriAt`) to the
#    expected URI.  RED pre-fix (no `U` token → no target); GREEN after.
( cd "$WT" && "$JABC" commit "commit:?$SHA" --tlv ) >"$WORK/jab.tlv" 2>"$WORK/jab.err2" \
    || _fail "jab commit --tlv failed ($(cat "$WORK/jab.err2"))"
[ -s "$WORK/jab.tlv" ] || _fail "jab commit --tlv emitted ZERO bytes"

"$JABC" "$_CASE/check.js" "$WORK/jab.tlv" "tree:?$TREE" "commit:?$PARENT" \
    >"$WORK/check.out" 2>&1 \
    || { cat "$WORK/check.out" >&2; _fail "U-target assertions failed"; }
grep -q "test/commit/links OK" "$WORK/check.out" \
    || { cat "$WORK/check.out" >&2; _fail "check.js did not report OK"; }
echo "ok: tree → tree:?<sha>, parent → commit:?<sha> (U targets via _uriAt)"

echo "PASS [$NAME]"
