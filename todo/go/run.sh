#!/bin/sh
# test/todo/go — TODO-005 `[go]`: the board's ONE creating button must MINT the
# ticket's worktree off its `Rep:` repo.  Driven through the REAL UI path (the
# test/todo/click model): fork a pty, `exec` the real `jab todo GO` in it, feed
# an SGR left-press at the cell `[go]` paints on, and assert the CLICK produced
# a populated `work/GO-001` — at the repo's LIVE rev, not the parent's stale pin.
#
# The fixture pins BOTH traps:
#  1. `Rep: ///sub` is written WITHOUT a trailing slash, exactly as all 16 real
#     `Rep:` values are.  The parent's gitlink pins the sub at s1 while the sub
#     itself is at s2 — so a verbatim clone checks out the DE-JURE stale pin and
#     the LIVE checkout is the only pass ([/wiki/URI] step 5.5).
#  2. the button is a CREATE, so the click must not push-nav to a refusal.
# Registered by the be/test glob as be-js-todo-go — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/todo/go
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "todo/go: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "todo/go: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/views/bro/pager.js" ] || { echo "todo/go: SKIP — no pager.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

command -v python3 >/dev/null 2>&1 || { echo "todo/go: SKIP — no python3" >&2; exit 0; }
python3 -c "import pty,select,fcntl,termios" 2>/dev/null \
    || { echo "todo/go: SKIP — no pty module" >&2; exit 0; }

: "${TMP:=/tmp}"; export TMP
NAME=go
WORK="$TMP/$$/todo/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [todo/$NAME] $*" >&2; exit 1; }

cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.size === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo no)
[ "$HAS" = "yes" ] || { echo "todo/go: SKIP — jab has no tty binding" >&2; exit 0; }

# --- the fixture -------------------------------------------------------------
WT="$WORK/wt"; mkdir -p "$WT/.be" "$WT/todo/GO" "$WT/work" "$WT/sub"
# the pairs are INDENTED four spaces, as every real ticket page writes them —
# a column-0 fixture hid pageHead's `^Key:` anchor bug (no Rep: ⇒ no button).
cat > "$WT/todo/GO/GO-001.mkd" <<'EOF'
#   GO-001: mint me
    Now: OPEN
    Rep: ///sub
EOF
# a ticket with no `Rep:` — the witness that the button is Rep-driven.
cat > "$WT/todo/GO/GO-002.mkd" <<'EOF'
#   GO-002: no repo
    Now: OPEN
EOF
cat > "$WT/.gitmodules" <<'EOF'
[submodule "sub"]
	path = sub
	url = git@example.invalid:nowhere/sub.git
EOF

# the SUB repo: the parent's gitlink pins s1 (`put sub` then post), then the sub
# moves on to s2 — so de-jure (`///sub`) and de-facto (`///sub/`) name DIFFERENT
# commits and the minted worktree's bytes say which one the button used.
( cd "$WT/sub" && mkdir -p .be && printf 's1\n' > f.txt && "$BE" post 's1' ) \
    >/dev/null 2>&1 || _fail "sub s1"
cd "$WT"
printf 'seed\n' > a.txt
"$BE" put sub >/dev/null 2>&1 || _fail "pin the sub"
"$BE" post 'seed commit' >/dev/null 2>&1 || _fail "seed post"
SEED=$(grep -o '[0-9a-f]\{40\}' "$WT/.be/wtlog" | tail -1)
[ -n "$SEED" ] || _fail "seed sha capture"
# GET-060: a store's SHARD dir — `.be/<title>/`, where the packs and the `refs`
# log live (RULING 2: there is no flat store, `.be/` holds shards only).  Read
# off disk, so a fixture never has to spell the title itself.
_shard() { dirname "$(ls "$1"/.be/*/*.keeper 2>/dev/null | head -1)"; }
printf '26718JF48j\tpost\t?#%s\n' "$SEED" > "$(_shard "$WT")/refs"
( cd "$WT/sub" && printf 's2\n' > f.txt && "$BE" post 's2' ) \
    >/dev/null 2>&1 || _fail "sub s2"

"$BE" todo GO --plain >/dev/null 2>&1 || _fail "the topic list does not render"

python3 "$_CASE/go.py" "$JABC" "$WT" >"$WORK/out" 2>"$WORK/err" || {
    echo "--- stderr ---"; cat "$WORK/err"
    echo "--- out ---";    cat "$WORK/out"; _fail "pty [go] click checks failed"; }
grep -q '^DONE' "$WORK/out" || { cat "$WORK/out"; _fail "the pty driver did not finish"; }
sed 's/^/     /' "$WORK/out"

echo "PASS [todo/$NAME]"
