#!/bin/sh
# DIFF-019 repro: a FILE-scoped `jab diff <file>` renders the WHOLE file
# ([DIFF-003]), so the render buffer scales with the FILE, not the edit.  On a
# ~100KB file that died `JS exception: Error: hunk.render: out full`, exit 1,
# zero output (the C side buffers had fixed 64K/4K caps; the JS call site had a
# fixed out buffer and no retry) — or, WORSE, exited 0 having silently dropped
# lines once a 4KB region buffer filled.  Now the C buffers are content-sized
# with every feed checked, and views/diff/diff.js grows-and-replays the out
# buffer on "out full" (degrading LOUDLY to windowed hunks over the hard cap).
# This is a REPRO test: exit 0, no "out full", no degrade warning, and the +/-
# line counts must match the file EXACTLY — no silent drops.
#
# Leg (a): every line of a 1500-line (~100KB) file edited.
# Leg (b): tiny base -> big target (3 -> 1530 lines), the truncation leg.
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

# --- leg (a): ~100KB file, every line changed ---------------------------
N=1500
awk -v n="$N" 'BEGIN { for (i = 1; i <= n; i++)
    printf "line %04d original content padding padding padding padding xyz\n", i }' > big.txt
# TEST-003: bare bootstrap post (no pre-put — a leading `jab put` corrupts the
# store bootstrap; `post ?trunk` auto-stages the fresh file).
"$BE" post -m v1 '?trunk' >/dev/null 2>&1
# DIS-076: a message-post never mints/moves a ref — publish the tag explicitly.
"$BE" post '?trunk' >/dev/null 2>&1

sed 's/original/MASSIVELY-CHANGED-LINE-CONTENT-AAAA/' big.txt > big.txt.t
mv big.txt.t big.txt

# diff_eq drives BOTH --plain (into $WORK/j.plain) and --color, and fails on a
# nonzero exit / empty output — the pre-fix mode (exit 1, zero bytes).
diff_eq "100KB file scope full" 'diff:big.txt'
if grep -qi 'out full' "$WORK/j.perr"; then
    echo "--- stderr ---"; head -20 "$WORK/j.perr"
    _fail "100KB whole-file render threw 'out full' (grow-on-full missing)"
fi
if grep -qi 'too big to render' "$WORK/j.perr"; then
    echo "--- stderr ---"; head -20 "$WORK/j.perr"
    _fail "100KB whole-file render degraded to hunks (out buffer too small)"
fi
have "^@@ -1,$N \+1,$N @@" "100KB file scope: whole-file hunk header"
plus=$(grep -c '^+line ' "$WORK/j.plain" || true)
minus=$(grep -c '^-line ' "$WORK/j.plain" || true)
[ "$plus" = "$N" ] || _fail "whole-file render dropped added lines ($plus of $N '+')"
[ "$minus" = "$N" ] || _fail "whole-file render dropped removed lines ($minus of $N '-')"
echo "ok   100KB whole-file render complete ($plus '+', $minus '-')"

# --- leg (b): tiny base, big target (the silent-truncation leg) ---------
M=1530
printf 'a\nb\nc\n' > grow.txt
"$BE" put grow.txt >/dev/null 2>&1
"$BE" post -m v2 '?trunk' >/dev/null 2>&1
"$BE" post '?trunk' >/dev/null 2>&1

awk -v n="$M" 'BEGIN { for (i = 1; i <= n; i++)
    printf "added line %04d some content here to make the line long enough\n", i }' > grow.txt

diff_jab "tiny base -> big target" 'diff:grow.txt'
if grep -qi 'out full' "$WORK/j.perr"; then
    echo "--- stderr ---"; head -20 "$WORK/j.perr"
    _fail "tiny-base/big-target render threw 'out full'"
fi
add=$(grep -c '^+added line ' "$WORK/j.plain" || true)
[ "$add" = "$M" ] || _fail "tiny-base/big-target dropped lines ($add of $M '+')"
del=$(grep -c '^-[abc]$' "$WORK/j.plain" || true)
[ "$del" = 3 ] || _fail "tiny-base/big-target lost the base lines ($del of 3 '-')"
echo "ok   tiny base -> big target renders every added line ($add of $M)"

pass
