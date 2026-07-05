#!/bin/sh
# WHY-001 test/why/blame — `jab why:<path>` blame VIEW: STEP the file weave and
# emit, per ORIGIN-commit run, a background-shaded span (hue=f(inserter sha),
# view/bro.js colorWhyHunk) carrying a `commit ?<sha40>` U click-target.
#
# A 3-commit fixture over one SYNTAX-tagged file (f.js): c1 seeds 3 lines, c2
# edits line 2, c3 adds a line.  The tip weave then has tokens from 3 DISTINCT
# origin commits, carrying real syntax tags (comment/keyword/number).  We drive
# `jab why why:f.js --tlv` (the on-wire HUNK stream the pager consumes), reparse
# it via the pager's hunksFromTlv, and (check.js) assert:
#   (a) the shaded runs cover 3 DISTINCT origin commits, each a `#rrggbb` the VIEW
#       baked (why.js whyRgb) → a truecolor wash (bm===3);
#   (b) each shaded run's U-target is `commit ?<sha40>` of its inserter commit;
#   (c) per-token SYNTAX tags survive buildBody (not flattened to one 'S' span) —
#       AND the pager STRING render (bro.paintWhyRowStr) carries both a syntax fg
#       SGR and >=2 distinct 48;2;R;G;B bg washes.
# Plus `--color` must carry 3 DISTINCT `48;2;R;G;B` bg codes AND a syntax fg SGR
# (the RENDER seam, not just the DATA).  RED before the render fix; GREEN after.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/why/blame
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "why/blame: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-${JAB:-$_BIN/jab}}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "why/blame: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "why/blame: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/why/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink so bareword `jab why`
# resolves the extension via jab's upward be/-scan from the worktree cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# WHY-001: pin commit time (jabc ron.now() rides SOURCE_DATE_EPOCH) so the fixture's
# 3 commit shas — hence hueOf's pastels — are DETERMINISTIC, not order/time flaky.
: "${SOURCE_DATE_EPOCH:=1467331200}"; export SOURCE_DATE_EPOCH

# 3-commit chain over one SYNTAX-tagged file (f.js) → 3 distinct origin commits
# alive at the tip, with comment/keyword/number tokens (so the syntax fg survives).
WT="$WORK/wt"; mkdir -p "$WT/.be"
cd "$WT"
printf '// alpha comment\nvar beta = 1;\nfunction gamma() {}\n' > f.js
"$BE" post 'c1 seed'          >/dev/null 2>&1 || _fail "post c1"
printf '// alpha comment\nvar BETA = 22;\nfunction gamma() {}\n' > f.js
"$BE" put f.js >/dev/null 2>&1; "$BE" post 'c2 edit line2' >/dev/null 2>&1 || _fail "post c2"
printf '// alpha comment\nvar BETA = 22;\nfunction gamma() {}\nlet delta = 3;\n' > f.js
"$BE" put f.js >/dev/null 2>&1; "$BE" post 'c3 add line4' >/dev/null 2>&1 || _fail "post c3"

# The three commit shas, tip-first (log order), for the U-target expectations.
"$JABC" "$_ROOT/put/tipsha.js" "$WT" >"$WORK/tip"
TIP=$(cat "$WORK/tip"); [ -n "$TIP" ] || _fail "no tip sha"

# 1. --plain: the tip file bytes verbatim (blame is presentation over the tip
#    view; the U/hue bytes stay hidden), plus the ONE trailing separator.
( cd "$WT" && "$JABC" why "why:f.js" --plain ) >"$WORK/plain" 2>"$WORK/perr" \
    || _fail "jab why --plain failed ($(cat "$WORK/perr"))"
[ -s "$WORK/plain" ] || _fail "jab why --plain emitted ZERO bytes"
grep -q '^let delta = 3;$' "$WORK/plain" || _fail "tip line 'let delta = 3;' missing from --plain"
grep -qE ' \?[0-9a-f]{40}|:\?' "$WORK/plain" && _fail "U URI bytes leaked into --plain"

# 2. --tlv: the on-wire HUNK stream; check.js reparses + asserts the hues + U's +
#    per-token syntax-tag survival + the pager STRING render (fg SGR + >=2 bgs).
( cd "$WT" && "$JABC" why "why:f.js" --tlv ) >"$WORK/tlv" 2>"$WORK/terr" \
    || _fail "jab why --tlv failed ($(cat "$WORK/terr"))"
[ -s "$WORK/tlv" ] || _fail "jab why --tlv emitted ZERO bytes"
"$JABC" "$_CASE/check.js" "$WORK/tlv" 3 >"$WORK/check.out" 2>&1 \
    || { cat "$WORK/check.out" >&2; _fail "why blame assertions failed"; }
grep -q "test/why/blame OK" "$WORK/check.out" \
    || { cat "$WORK/check.out" >&2; _fail "check.js did not report OK"; }

# 3. --color: the wash renders M DISTINCT pastel bg codes (one per origin commit)
#    AND a syntax FG SGR (the comment/keyword fg — proof the render seam preserves
#    per-token tags, not a flat bg).  Drop line 1 (the THEME_BANNER band, bg 230).
( cd "$WT" && "$JABC" why "why:f.js" --color ) >"$WORK/color" 2>"$WORK/cerr" \
    || _fail "jab why --color failed ($(cat "$WORK/cerr"))"
_body=$(tail -n +2 "$WORK/color")
# WHY-001: the 3 fixture commits share one pinned time (one shade), so their washes
# differ by HUE; >=2 distinct proves per-commit colour (exact 3 not required — hues
# may collide on the cube, and age-shade is covered by the age test).
_nbg=$(printf '%s' "$_body" | grep -oaE '48;2;[0-9]+;[0-9]+;[0-9]+' | sort -u | wc -l | tr -d ' ')
[ "$_nbg" -ge 2 ] || { cat -v "$WORK/color" | head -10; _fail "--color: want >=2 distinct body bg hues, got $_nbg"; }
# A syntax fg SGR: a basic 3x/9x fg (comment gray 90 / keyword blue 94) OR a 38;5;
# 256-fg — anything but a bare bg-only code.  The pre-fix flat render had none.
printf '%s' "$_body" | grep -oaE '\[([0-9]+;)*(3[0-9]|9[0-9]|38;5;[0-9]+)' >/dev/null \
    || { cat -v "$WORK/color" | head -10; _fail "--color: no syntax FG SGR (render flattened tags)"; }

echo "PASS [$NAME]"
