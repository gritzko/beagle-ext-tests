#!/bin/sh
# test/todo/nav — TODO-008: a meta pair whose VALUE lexes as a ticket id
# NAVIGATES to that ticket, it does not swap a filter.  Driven through the
# REAL UI path (the test/todo/click model): a pty, the real `jab todo …` in
# it (isatty(1) -> the universal bro pager, JAB-030), a real SGR left-press
# report on the cell the value paints on, and the repainted frame as the
# evidence.  The pager stays arg-blind — it drives the O spell and the `todo`
# VERB resolves the arg (BRO-025 / the Nav design law).
#
# RED before the fix: TODO-004 hung the whole-arg-line filter spell on BOTH
# halves, so clicking `See: NAV-002` answered `todo NAV See:NAV-002` — and a
# ticket-valued key is presence-filterable ONLY (a colon-free code still
# filters, but the answer is the pointing ticket, never the pointed-at one),
# so the click was dead weight exactly where a jump is wanted.
#
# What the case pins:
#   page  `See: NAV-002`  value click -> `todo NAV-002` (the target's PAGE)
#   page  `Zzz: NAV-003`  value click -> `todo NAV-003` (an UNREGISTERED key:
#                                        the VALUE's lexical class decides)
#   page  `See:`          KEY   click -> `todo NAV See:*` (unchanged)
#   board `[NAV-002]` inline value click -> `todo NAV-002`
# Registered by the be/test glob as be-js-todo-nav — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/todo/nav
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "todo/nav: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "todo/nav: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/views/bro/pager.js" ] || { echo "todo/nav: SKIP — no pager.js" >&2; exit 0; }
[ -f "$BEDIR/shared/metaidx.js" ] || { echo "todo/nav: SKIP — no metaidx.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

command -v python3 >/dev/null 2>&1 || { echo "todo/nav: SKIP — no python3" >&2; exit 0; }
python3 -c "import pty,select,fcntl,termios" 2>/dev/null \
    || { echo "todo/nav: SKIP — no pty module" >&2; exit 0; }

: "${TMP:=/tmp}"; export TMP
NAME=nav
WORK="$TMP/$$/todo/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [todo/$NAME] $*" >&2; exit 1; }

# SKIP if the jab build lacks the tty binding (pre-JS-053: no pager at all).
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.size === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo no)
[ "$HAS" = "yes" ] || { echo "todo/nav: SKIP — jab has no tty binding" >&2; exit 0; }

# --- the fixture ------------------------------------------------------------
# NAV-001's page must paint its pairs on KNOWN cells: the header is file line 1
# and the block starts at line 2, and the pager paints the banner on screen
# row 1 — so `Now:` is row 3, `See:` row 4 and `Zzz:` row 5, each key on
# columns 1-4 and each value on columns 6-13.
# `Zzz:` is a key no [/meta/todo] entry registers: its ticket-shaped value must
# navigate all the same (the VALUE's lexical class alone decides).
WT="$WORK/wt"; mkdir -p "$WT/.be" "$WT/todo/NAV"
cat > "$WT/todo/NAV/NAV-001.mkd" <<'EOF'
#   NAV-001: alpha
Now: OPEN
See: NAV-002
Zzz: NAV-003
EOF
cat > "$WT/todo/NAV/NAV-002.mkd" <<'EOF'
#   NAV-002: beta
Now: OPEN
EOF
cat > "$WT/todo/NAV/NAV-003.mkd" <<'EOF'
#   NAV-003: gamma
Now: OPEN
EOF

cd "$WT"
printf 'seed\n' > a.txt
"$BE" post 'seed commit' >/dev/null 2>&1 || _fail "seed post"
# the store must answer before the pty leg (a first sweep inside the pager
# would still work, but a failure there would read as a click failure).
"$BE" todo NAV-001 --plain >/dev/null 2>&1 || _fail "the ticket page does not render"
"$BE" todo NAV 'See:*' --plain >/dev/null 2>&1 || _fail "the inline-value board does not render"

python3 "$_CASE/nav.py" "$JABC" "$WT" >"$WORK/out" 2>"$WORK/err" || {
    echo "--- stderr ---"; cat "$WORK/err"
    echo "--- out ---";    cat "$WORK/out"; _fail "pty click checks failed"; }
grep -q '^DONE' "$WORK/out" || { cat "$WORK/out"; _fail "the pty driver did not finish"; }
sed 's/^/     /' "$WORK/out"

echo "PASS [todo/$NAME]"
