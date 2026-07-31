#!/bin/sh
# test/bro/elastic — BRO-036 elastic fields: tok tag `B` marks the ONE per-line
# span the pager resizes in NO-WRAP mode — `…`-cut on overflow so the trailing
# columns ([done]) stay visible, space-pad on underflow so they end flush right
# at cols.  Fixture: a REAL todo board (one LONG-titled + one short-titled open
# ticket); `jab todo ELS --tlv` captures the REAL producer stream, then
# elastic.js drives the REAL Pager over a tty.openpty() slave (40 cols) and
# asserts the frame + the click path.  RED before the fix: the title span
# carries no `B`, the long row hard-clips at 40 eating `[done]`, the short row
# is not padded.  Piped --plain stays verbatim (no trim, no pad) throughout.
# Registered by the be/test glob as be-js-bro-elastic — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/bro/elastic
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "bro/elastic: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "bro/elastic: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/views/bro/pager.js" ] || { echo "bro/elastic: SKIP — no pager.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=elastic
WORK="$TMP/$$/bro/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the jsrc symlink (bareword `jab todo` resolves via jab's
# upward jsrc/-scan from the worktree cwd).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [bro/$NAME] $*" >&2; exit 1; }

# tty-binding probe (the pty leg needs openpty); SKIP cleanly if absent.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.raw === "function" &&
           typeof tty.openpty === "function" && typeof tty.size === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo err)
[ "$HAS" = "yes" ] || { echo "bro/elastic: SKIP — jab has no tty binding (got '$HAS')" >&2; exit 0; }

# --- the fixture board: one LONG-titled + one short-titled open ticket ------
# URI-016: todoRoot() is <project root>/todo; the wt's `.be/` shield IS the
# project-root anchor, so the board lives UNDER the wt (the todo/view model).
WT="$WORK/wt"; mkdir -p "$WT/.be" "$WT/todo/ELS"
cat > "$WT/todo/ELS/ELS-1.mkd" <<'EOF'
#   ELS-1: a very long elastic ticket title that runs far past forty columns of terminal
EOF
cat > "$WT/todo/ELS/ELS-2.mkd" <<'EOF'
#   ELS-2: tiny
EOF
cd "$WT"
printf 'seed\n' > a.txt
"$BE" post 'seed commit' >/dev/null 2>&1 || _fail "seed post"

# --- the REAL producer stream + the verbatim --plain guard ------------------
"$BE" todo ELS --tlv > "$WORK/els.tlv" 2>/dev/null || _fail "jab todo ELS --tlv failed"
[ -s "$WORK/els.tlv" ] || _fail "todo --tlv emitted ZERO bytes"
"$BE" todo ELS --plain > "$WORK/els.plain" 2>/dev/null || _fail "jab todo ELS --plain failed"
grep -q 'a very long elastic ticket title that runs far past forty columns of terminal' \
    "$WORK/els.plain" || _fail "--plain trimmed/padded the title (must be verbatim)"

# --- the pty leg: the REAL Pager over the captured stream -------------------
"$JABC" "$_CASE/elastic.js" "$BEDIR/views/bro/pager.js" "$BEDIR/view/bro.js" \
    "$BEDIR/views/work/work.js" "$WORK/els.tlv" >"$WORK/e.out" 2>"$WORK/e.err" || {
    echo "--- stderr ---"; cat "$WORK/e.err"; _fail "elastic.js exited non-zero"; }
if grep -q '^FAIL' "$WORK/e.out"; then
    echo "--- out ---"; cat "$WORK/e.out"; _fail "elastic check(s) failed"; fi
grep -q '^DONE' "$WORK/e.out" || { echo "--- out ---"; cat "$WORK/e.out"; _fail "driver did not finish"; }
echo "ok   elastic B field: producers tag B; pty no-wrap …-cut + flush-right pad"
echo "PASS [bro/$NAME]"
exit 0
