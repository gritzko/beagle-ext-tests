#!/bin/sh
# test/bro/spelldrive — CODE-030: the address-bar SPELL DRIVE (buildHunks /
# spellCall / driveSpell) moved out of views/bro/bro.js into core/loop.js, and
# bro's tty branch now calls loop.openPager — the move that broke the
# core/loop.js <-> views/bro/bro.js require cycle.  This case proves the path
# through the REAL pager UI (a pty.fork'd `jab bro`, a typed `:` spell, a real
# SGR mouse click), never a TLV/unit probe: drive.py runs the three legs and
# asserts the frame actually swapped each time, then `q` exits clean.
# SKIP-guarded like test/bro/universal (needs python3+pty and jab's tty binding).
. "$(dirname "$0")/../lib/brocase.sh"

[ -f "$BROWT/views/bro/pager.js" ] || { echo "spelldrive: SKIP — no pager at $BROWT" >&2; pass; }
grep -q 'openPager' "$BROWT/core/loop.js" 2>/dev/null || {
    echo "spelldrive: SKIP — loop.js has no openPager edge" >&2; pass; }

command -v python3 >/dev/null 2>&1 || { echo "spelldrive: SKIP — no python3" >&2; pass; }
python3 -c "import pty,select" 2>/dev/null || { echo "spelldrive: SKIP — no pty module" >&2; pass; }

# SKIP if the jab build lacks the tty binding (pre-JS-053) — the pager is blocked.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.raw === "function" &&
           typeof tty.openpty === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo err)
[ "$HAS" = "yes" ] || { echo "spelldrive: SKIP — jab has no tty binding (got '$HAS')" >&2; pass; }

# --- the fixture worktree (test/bro/universal's shape) ----------------------
# A project root (`.be/` anchor + `work/`, [/wiki/URI] steps 1-2) with the
# `jsrc` shard symlink so the bareword `jab bro` scan finds this JS tree, and
# `//UNI` under it — two posted text files, so every view renders real hunks.
. "$_ROOT/lib/repo-setup.sh"
SRC="$WORK/src"
WORKD=$(rs_work_root "$SRC")
ln -sfn "$BROWT" "$SRC/jsrc"
BE_ROOT="$WORK"; export BE_ROOT
FIX="$WORKD/UNI"
mkdir -p "$FIX/.be" "$FIX/sub" "$SRC/todo/UNI"
printf '#   UNI-1: the spelldrive fixture ticket\n' > "$SRC/todo/UNI/UNI-1.mkd"
printf 'alpha one\nbeta UNI-1 two\ngamma three\n' > "$FIX/hello.txt"
printf 'delta four\n' > "$FIX/sub/notes.txt"
( cd "$FIX" && "$JABC" post '#seed' ) >"$WORK/seed.out" 2>"$WORK/seed.err" || {
    echo "--- seed stderr ---"; cat "$WORK/seed.err"; _fail "fixture post failed"; }
_LSRC=0; ( cd "$FIX" && "$JABC" ls ) >"$WORK/probe.out" 2>"$WORK/probe.err" || _LSRC=$?
{ [ "$_LSRC" = 0 ] && [ -s "$WORK/probe.out" ]; } || {
    echo "--- probe stderr ---"; cat "$WORK/probe.err"
    _fail "fixture worktree renders nothing (jab ls rc=$_LSRC)"; }

python3 "$_CASE/drive.py" "$JABC" "$FIX" "$WORK" >"$WORK/d.out" 2>"$WORK/d.err" || {
    echo "--- stderr ---"; cat "$WORK/d.err"
    echo "--- out ---";    cat "$WORK/d.out"; _fail "spell-drive pty session failed"; }
grep -q '^DONE' "$WORK/d.out" || { echo "--- out ---"; cat "$WORK/d.out"; _fail "driver did not finish"; }
echo "ok   spell drive through the real pager (launch spell, typed :spell, mouse click)"
pass
