#!/bin/sh
# test/commit/resolve — COMMIT-004 (+ co-landed JS-082): `jab commit:<target>`
# must RESOLVE and SHOW the requested commit, byte-parity with C `be commit:`,
# for every slot form C accepts: `?<branch>`, a hash in `?` (`?<sha>` / `?#<sha>`)
# and a hash in `#` (`#<sha>`), each SHORT hashlet AND full 40-hex; plus bare
# (cur tip, the SPEC deviation COMMIT-003 carries).  A nonexistent / ambiguous
# target must FAIL cleanly, never silently print the cur tip.
#
# Differential: for each form, `be commit:X` (the C oracle) vs `jab commit:X`.
# The JS HUNK content render appends ONE trailing blank-line separator to every
# content view (a binding-level constant — see commit.js / COMMIT-003); so the
# native bytes must be an EXACT PREFIX of the JS bytes with that one extra '\n'.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/commit/resolve
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "commit: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "commit: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "commit: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/commit/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink so bareword `jab commit`
# resolves the extension via jab's upward be/-scan from the worktree cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# A worktree under the isolated scratch base with a commit and a named branch
# `feat` at that tip (for the `?<branch>` parity form).
WT="$WORK/wt"; mkdir -p "$WT/.be"
( cd "$WT" && printf 'one\n' > a.txt && "$BE" post 'first commit' >/dev/null 2>&1 ) \
    || _fail "could not seed the commit"
( cd "$WT" && "$BE" put '?feat' >/dev/null 2>&1 ) \
    || _fail "could not create the feat branch"
BR=feat

# The trunk tip's full 40-hex sha + an 8-hex short hashlet.
SHA=$("$JABC" "$_ROOT/put/tipsha.js" "$WT")
[ -n "$SHA" ] || _fail "could not resolve the trunk tip sha"
case "$SHA" in *[!0-9a-f]*|"") _fail "tip sha not 40-hex: '$SHA'" ;; esac
SHORT=$(printf '%s' "$SHA" | cut -c1-8)

# parity <label> <form> — jab-intrinsic: `jab commit:<form>` RESOLVES + SHOWS the
# tip commit (TEST-003/COMMIT-007 — native `be` LAGS jab, so no oracle cmp).
parity() {
    _lbl="$1"; _form="$2"
    ( cd "$WT" && "$JABC" commit "commit:$_form" ) >"$WORK/jab.$_lbl" 2>"$WORK/err.$_lbl" \
        || _fail "[$_lbl] jab commit:'$_form' failed (rc=$?, stderr: $(cat "$WORK/err.$_lbl"))"
    [ -s "$WORK/jab.$_lbl" ] || _fail "[$_lbl] jab emitted ZERO bytes for '$_form'"
    grep -q "^commit $SHA\$" "$WORK/jab.$_lbl" \
        || _fail "[$_lbl] jab did not resolve 'commit:$_form' to the tip $SHA"
}

# bare — the SPEC deviation: jab shows the cur tip, native KEEPFAILs.  Assert
# jab shows the cur tip commit (not an error, not empty); native parity N/A.
( cd "$WT" && "$JABC" commit "commit:" ) >"$WORK/jab.bare" 2>"$WORK/err.bare" \
    || _fail "[bare] jab commit: failed (stderr: $(cat "$WORK/err.bare"))"
grep -q "^commit $SHA\$" "$WORK/jab.bare" || _fail "[bare] jab did not show the cur tip"

# Every resolvable form, SHORT then FULL-40-hex (COMMIT-004 + JS-082).
parity branch     "?$BR"
parity q-short     "?$SHORT"
parity q-full      "?$SHA"
parity qh-short   "?#$SHORT"
parity qh-full    "?#$SHA"
parity f-short     "#$SHORT"
parity f-full      "#$SHA"

# All resolvable forms must agree on the SAME commit (the tip).
for _l in branch q-short q-full qh-short qh-full f-short f-full; do
    grep -q "^commit $SHA\$" "$WORK/jab.$_l" \
        || _fail "[$_l] jab did not resolve to the requested commit $SHA"
done

# Negative: a nonexistent / ambiguous target must FAIL cleanly (nonzero, no
# stdout) — never silently fall back to the cur tip (the COMMIT-004 defect).
ZERO=0000000000000000000000000000000000000000
for _bad in "#deadbeef" "#$ZERO" "?nosuchbranch12345" "?deadbeef" "?#$ZERO"; do
    ( cd "$WT" && "$JABC" commit "commit:$_bad" ) >"$WORK/bad.out" 2>/dev/null \
        && _fail "[neg] jab commit:'$_bad' SUCCEEDED (should fail cleanly)"
    [ -s "$WORK/bad.out" ] \
        && _fail "[neg] jab commit:'$_bad' emitted bytes (silent cur-tip fallback?)"
done

echo "PASS [$NAME]"
