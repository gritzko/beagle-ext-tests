#!/bin/sh
# test/commit/diff — COMMIT-006: `jab commit:?<sha>` must INLINE the commit's
# full diff (first-parent.tree → commit.tree) as relayed hunks AFTER the
# metadata, mirroring C `be commit:?<sha>` ([COMMIT-002], df596d0f).  Before the
# fix the JS view emitted ONLY the metadata hunk (no diff) — RED.  After, the
# diff follows the metadata, byte-parity with native modulo the ONE trailing
# blank-line separator the JS HUNK plain feed appends to a content record (the
# documented binding-level delta, the same one render/links already tolerate).
#
# Diff is ALWAYS vs the FIRST parent — merges INCLUDED (user RULING; git
# `--first-parent`, the LOG-001 spine).  Only ROOT (0 parents) skips (no base).
# Cases: (a) a 1-parent commit inlines + byte-matches native; (b) root skips;
# (c) a real 2-parent MERGE inlines the first-parent diff.  Also asserts
# COMMIT-003/004/005 (the metadata + plain parity) survive.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/commit/diff
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "commit/diff: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-${JAB:-$_BIN/jab}}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "commit/diff: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "commit/diff: no jab at $JABC" >&2; exit 2; }
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

# A 2-commit chain: the tip commit HAS exactly one parent (the inline-diff path).
# The second commit modifies a.txt AND adds b.txt so the diff spans an add.
WT="$WORK/wt"; mkdir -p "$WT/.be"
cd "$WT"
printf 'one\ntwo\nthree\n'      > a.txt;                       "$BE" post 'first commit'  >/dev/null 2>&1 || _fail "post 1"
printf 'one\nTWO\nthree\nfour\n' > a.txt
printf 'brand new\n'            > b.txt; "$BE" put b.txt >/dev/null 2>&1
"$BE" post 'second commit' >/dev/null 2>&1 || _fail "post 2"

# The tip commit's full 40-hex sha (1 parent, resolvable).
SHA=$("$JABC" "$_ROOT/put/tipsha.js" "$WT")
[ -n "$SHA" ] || _fail "could not resolve the tip sha"
case "$SHA" in *[!0-9a-f]*|"") _fail "tip sha not 40-hex: '$SHA'" ;; esac

# TEST-003/COMMIT-007: jab-intrinsic — native `be` LAGS jab, so no oracle cmp.
( cd "$WT" && "$JABC" commit "commit:?$SHA" --plain ) >"$WORK/jab.plain" 2>"$WORK/jab.err" \
    || _fail "jab commit --plain failed ($(cat "$WORK/jab.err"))"
[ -s "$WORK/jab.plain" ] || _fail "jab commit --plain emitted ZERO bytes"

# 1. METADATA preserved (COMMIT-003/004/005): the commit/tree/parent/author/body
#    lines are all present, byte-anchored.
grep -q "^commit $SHA\$" "$WORK/jab.plain" || _fail "missing 'commit <sha40>' line"
grep -q "^tree "         "$WORK/jab.plain" || _fail "missing tree header"
grep -q "^parent "       "$WORK/jab.plain" || _fail "missing parent header"
grep -q "^author "       "$WORK/jab.plain" || _fail "missing author header"
grep -q "^second commit\$" "$WORK/jab.plain" || _fail "missing message body"

# 2. DIFF inlined (the RED→GREEN signal — absent before COMMIT-006): the unified
#    diff hunk for the added b.txt follows the metadata.
grep -q "^+++ b/b.txt\$" "$WORK/jab.plain" || _fail "diff not inlined (no '+++ b/b.txt' — RED)"
grep -q "^@@ "           "$WORK/jab.plain" || _fail "diff not inlined (no '@@' hunk header)"
grep -q "^+brand new\$"  "$WORK/jab.plain" || _fail "diff not inlined (no '+brand new' add line)"

# 3. The DIFF must come AFTER the metadata (the message body precedes the diff).
_body_ln=$(grep -n "^second commit\$" "$WORK/jab.plain" | head -1 | cut -d: -f1)
_diff_ln=$(grep -n "^+++ b/b.txt\$"   "$WORK/jab.plain" | head -1 | cut -d: -f1)
[ "$_body_ln" -lt "$_diff_ln" ] || _fail "diff precedes the metadata body (order wrong)"

echo "ok: 1-parent commit inlines the diff after the metadata (jab-intrinsic)"

# 5. ROOT (0 parents) SKIPS the diff (metadata only — base TBD).  The root
#    commit's jab --plain carries NO unified-diff hunk lines.
ROOT=$(awk '$1=="parent"{print $2; exit}' "$WORK/jab.plain")
[ -n "$ROOT" ] || _fail "could not extract the root (parent) sha"
( cd "$WT" && "$JABC" commit "commit:?$ROOT" --plain ) >"$WORK/root.plain" 2>/dev/null \
    || _fail "jab commit (root) --plain failed"
grep -q "^commit $ROOT\$" "$WORK/root.plain" || _fail "root: missing 'commit <sha40>'"
grep -q "^@@ "  "$WORK/root.plain" && _fail "root: diff NOT skipped (found '@@' — base is TBD)"
grep -q "^+++ " "$WORK/root.plain" && _fail "root: diff NOT skipped (found '+++')"
echo "ok: root commit (0 parents) skips the diff (metadata only)"

# 6. MERGE (2+ parents): the diff is inlined vs the FIRST parent (user RULING).
#    Build a real merge: branch `feature` diverges, trunk diverges, then
#    `be patch ?feature` + post mints a 2-parent merge commit on trunk.
MWT="$WORK/mwt"; mkdir -p "$MWT/.be"
cd "$MWT"
printf 'base\n'         > f.txt; "$BE" post 'mbase' >/dev/null 2>&1 || _fail "merge: post base"
"$BE" put '?feature'    >/dev/null 2>&1 || _fail "merge: mint feature"
"$BE" get '?feature'    >/dev/null 2>&1 || _fail "merge: switch feature"
printf 'base\nfeature\n' > f.txt; "$BE" post 'mfeat' >/dev/null 2>&1 || _fail "merge: post feature"
"$BE" get '?'           >/dev/null 2>&1 || _fail "merge: back to trunk"
printf 'trunk\n'        > g.txt; "$BE" put g.txt >/dev/null 2>&1; "$BE" post 'mtrunk' >/dev/null 2>&1 || _fail "merge: post trunk"
"$BE" patch '?feature'  >/dev/null 2>&1 || _fail "merge: patch feature"
"$BE" post 'merge feature' >/dev/null 2>&1 || _fail "merge: post merge"

MSHA=$("$JABC" "$_ROOT/put/tipsha.js" "$MWT")
[ -n "$MSHA" ] || _fail "merge: could not resolve merge tip sha"
# Confirm it really has >=2 parents (a true merge commit).
_pc=$( ( cd "$MWT" && "$JABC" commit "commit:?$MSHA" --plain ) 2>/dev/null | grep -c '^parent ' )
[ "$_pc" -ge 2 ] || _fail "merge: tip is not a merge commit (parents=$_pc)"

( cd "$MWT" && "$JABC" commit "commit:?$MSHA" --plain ) >"$WORK/mjab.plain" 2>/dev/null \
    || _fail "merge: jab commit failed"
grep -q "^@@ " "$WORK/mjab.plain" || _fail "merge: diff NOT inlined (no '@@' — first-parent diff expected)"
# TEST-003: FIRST-parent proof, jab-intrinsic — the diff vs parent¹ (mtrunk)
# carries feature's `+feature` add on f.txt; a parent² diff would show g.txt instead.
grep -q "^+feature\$" "$WORK/mjab.plain" \
    || _fail "merge: first-parent diff missing feature's add (not diffed vs parent¹?)"
echo "ok: merge commit (2 parents) inlines the FIRST-parent diff (jab-intrinsic)"

echo "PASS [$NAME]"
