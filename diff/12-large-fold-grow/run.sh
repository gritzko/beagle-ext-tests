#!/bin/sh
# DIFF-010 repro: a large diff's `weave.fold` must NOT throw "out full".  The
# JS diff fold (views/diff/diff.js diffFile -> weave.fold) used a fixed WEAVE
# buffer, so a commit with a large change overflowed it ("weave.fold: failed
# (out full?)").  Surfaced live via `commit:?<sha>` (COMMIT-006 inline diff,
# which reuses the diff GENERATOR).  After DIFF-010 the fold grows-on-full +
# retries (shared/weave.js, mirroring core/loop.js:128-142), so the full diff
# renders.  This is a REPRO test (not a JS-vs-native parity case): it asserts
# the loop no longer errors and the changed lines are present.
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

# A big file: ~2800 lines.  The 'W' weave blob (toks + columns) is bigger than
# the raw text, so even ~175 KB of content overflows the old fixed 1<<18 =
# 256 KB WEAVE fold buffer — folding ONE revision already threw pre-fix.
awk 'BEGIN { for (i = 1; i <= 2800; i++)
    printf "line %04d original content padding padding padding padding xyz\n", i }' > big.txt
# TEST-003: bare bootstrap post (no pre-put — a leading `jab put` corrupts the
# store bootstrap; `post ?trunk` auto-stages the fresh file).
"$BE" post -m v1 '?trunk' >/dev/null 2>&1
# DIS-076: a message-post never mints/moves a ref — publish the `trunk` tag
# explicitly (the `post "?<branch>"` pattern) so `sha1:'?trunk'` stays resolvable.
"$BE" post '?trunk' >/dev/null 2>&1

# v2: change EVERY line — a large diff whose weave fold overflows the old cap.
sed 's/original/MASSIVELY-CHANGED-LINE-CONTENT-AAAA/' big.txt > big.txt.t && mv big.txt.t big.txt
"$BE" put big.txt >/dev/null 2>&1
"$BE" post -m v2 '?trunk' >/dev/null 2>&1
"$BE" post '?trunk' >/dev/null 2>&1

# TEST-003: resolve the v2 tip via jab's sha1: (log:'s header row breaks the old
# awk column grab; sha1:'?trunk' is the jab-native tip lookup).
SHA=$("$JABC" sha1:'?trunk' 2>/dev/null | grep -oE '^[0-9a-f]{40}')
[ -n "$SHA" ] || _fail "could not resolve v2 commit sha"

# Drive the live repro: `jab commit:?<sha>` (COMMIT-006 inline diff over the
# diff GENERATOR).  RED pre-fix: exit 1 + "weave.fold: failed (out full?)".
rc=0
"$JABC" "commit:?$SHA" --plain >"$WORK/out.txt" 2>"$WORK/err.txt" || rc=$?

# (1) no "out full" / weave.fold throw anywhere.
if grep -qi 'out full\|weave\.fold' "$WORK/err.txt"; then
    echo "--- stderr ---"; cat "$WORK/err.txt" | head -20
    _fail "weave.fold overflowed on a large diff (out full) — grow-on-full missing"
fi
# (2) clean exit.
[ "$rc" = 0 ] || { echo "--- stderr ---"; cat "$WORK/err.txt" | head -20
    _fail "commit:?<sha> exited $rc on a large diff"; }
# (3) the diff rendered: the metadata header AND changed lines (the tree-scope
# `commit:` diff is WINDOWED — emitDiff shows a window, not every line; pre-fix
# the fold threw before ANY line, so a non-empty changed body proves the fix).
grep -q '^--- a/big.txt' "$WORK/out.txt" || _fail "diff header missing (empty diff)"
n=$(grep -c 'MASSIVELY-CHANGED-LINE-CONTENT-AAAA' "$WORK/out.txt")
[ "$n" -ge 10 ] || _fail "large diff body missing (only $n changed lines rendered)"
echo "ok   large-fold diff renders ($n changed lines, exit $rc, no out-full)"

# Small-diff guard: a tiny change still renders cleanly (fix is transparent).
printf 'a\nb\nc\n' > tiny.txt
"$BE" put tiny.txt >/dev/null 2>&1
"$BE" post -m v3 '?trunk' >/dev/null 2>&1
"$BE" post '?trunk' >/dev/null 2>&1
SHA3=$("$JABC" sha1:'?trunk' 2>/dev/null | grep -oE '^[0-9a-f]{40}')
rc=0
"$JABC" "commit:?$SHA3" --plain >"$WORK/out3.txt" 2>"$WORK/err3.txt" || rc=$?
[ "$rc" = 0 ] || _fail "small-diff commit:?<sha> regressed (exit $rc)"
grep -q '^+a' "$WORK/out3.txt" || _fail "small diff body missing"
echo "ok   small diff unaffected"

pass
