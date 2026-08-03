#!/bin/sh
# test/todo/click — TODO-004: the meta-pair CLICK round-trips, driven through
# the REAL UI path.  Not a tlv probe and not a hand-built Pager: this forks a
# pty, `exec`s the real `jab todo …` in it (isatty(1) → the universal bro
# pager, JAB-030), feeds a real SGR left-press report at the cell the meta
# pair paints on, and asserts the PAINTED FRAME flips to the answer the spell
# names.  The pager stays arg-blind throughout — it drives the O spell, and
# the `todo` VERB resolves the arg (BRO-025).
#
# The ruling this pins (2026-08-03): a click REPLACES that key's filter and
# leaves the REST of the arg line alone, because the spell carries the WHOLE
# arg line (never a `todo(key,value)` call).  The painted BANNER is the address
# bar, so the round-trips read straight off the frame:
#   `todo CLK Now:*`       click OPEN -> `todo CLK Now:OPEN`
#     back, then           click DONE -> `todo CLK Now:DONE`  (REPLACED — not
#                                        two filters, not a fresh line)
#   `todo CLK Now:* Sev:*` click HIGH -> `todo CLK Now:* Sev:HIGH`
#   ticket page CLK-001    click Now: -> `todo CLK Now:*`
#   ticket page CLK-001    click OPEN -> `todo CLK Now:OPEN`
# Registered by the be/test glob as be-js-todo-click — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/todo/click
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "todo/click: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "todo/click: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/views/bro/pager.js" ] || { echo "todo/click: SKIP — no pager.js" >&2; exit 0; }
[ -f "$BEDIR/shared/metaidx.js" ] || { echo "todo/click: SKIP — no metaidx.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

# The driver is a controlling-terminal harness (the test/bro/universal model).
command -v python3 >/dev/null 2>&1 || { echo "todo/click: SKIP — no python3" >&2; exit 0; }
python3 -c "import pty,select,fcntl,termios" 2>/dev/null \
    || { echo "todo/click: SKIP — no pty module" >&2; exit 0; }

: "${TMP:=/tmp}"; export TMP
NAME=click
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
[ "$HAS" = "yes" ] || { echo "todo/click: SKIP — jab has no tty binding" >&2; exit 0; }

# --- the fixture (the todo/meta model, kept SHORT so no row soft-wraps) -----
# CLK-001's page must paint `Now: OPEN` on a KNOWN cell: the header is file
# line 1 and the pair block starts at line 2, and the pager paints the banner
# on screen row 1 — so `Now:` is row 3, columns 1-4, and its value columns 6-9.
# In a LISTING the rows are topic+number ordered (time-sort is postponed), so
# CLK-001/2/3 land on screen rows 2/3/4 and every inline value opens at column
# 10 (`CLK-001` 1-7, ` ` 8, `[` 9).
WT="$WORK/wt"; mkdir -p "$WT/.be" "$WT/todo/CLK"
cat > "$WT/todo/CLK/CLK-001.mkd" <<'EOF'
#   CLK-001: alpha
Now: OPEN
Sev: HIGH
EOF
cat > "$WT/todo/CLK/CLK-002.mkd" <<'EOF'
#   CLK-002: beta
Now: OPEN
Sev: LOW
EOF
# the ONLY closed ticket: the witness.  The implicit `Now:` default hides it,
# `Now:*` shows it (so a DONE value is on screen to click), and `Now:DONE` is
# what the click must leave behind.
cat > "$WT/todo/CLK/CLK-003.mkd" <<'EOF'
#   CLK-003: gamma
Now: DONE
EOF

cd "$WT"
printf 'seed\n' > a.txt
"$BE" post 'seed commit' >/dev/null 2>&1 || _fail "seed post"
# the store must answer before the pty leg (a first sweep inside the pager
# would still work, but a failure there would read as a click failure).
"$BE" todo --plain >/dev/null 2>&1 || _fail "the board does not render at all"

python3 "$_CASE/click.py" "$JABC" "$WT" >"$WORK/out" 2>"$WORK/err" || {
    echo "--- stderr ---"; cat "$WORK/err"
    echo "--- out ---";    cat "$WORK/out"; _fail "pty click checks failed"; }
grep -q '^DONE' "$WORK/out" || { cat "$WORK/out"; _fail "the pty driver did not finish"; }
sed 's/^/     /' "$WORK/out"

echo "PASS [todo/$NAME]"
