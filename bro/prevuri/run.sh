#!/bin/sh
# test/bro/prevuri — DIS-061: the pager stashes the CURRENT view's file into the
# ambient `be.prev_uri` bridge (single-hunk FILE view only; multi-hunk / dir /
# empty clears it; recomputed on push / pop-back / re-drive), and the named
# FILE-focused verbs (why, vim) consume it as their no-arg default — WITHOUT the
# pager welding any implied argument into the spell.  One headless driver over
# views/bro/pager.js + views/why/why.js + verbs/vim/vim.js, SKIP-guarded like
# the sibling pager cases.
. "$(dirname "$0")/../lib/brocase.sh"

PAGER="${PAGER_LIB:-$BROWT/views/bro/pager.js}"
WHY="$BROWT/views/why/why.js"
VIM="$BROWT/verbs/vim/vim.js"
[ -f "$PAGER" ] || { echo "prevuri: SKIP — no views/bro/pager.js at $BROWT" >&2; pass; }
[ -f "$WHY" ]   || { echo "prevuri: SKIP — no views/why/why.js at $BROWT" >&2; pass; }
[ -f "$VIM" ]   || { echo "prevuri: SKIP — no verbs/vim/vim.js at $BROWT" >&2; pass; }

# SKIP if the jab build lacks the tty binding — the driver stubs tty.size.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.size === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo err)
[ "$HAS" = "yes" ] || { echo "prevuri: SKIP — jab has no tty binding (got '$HAS')" >&2; pass; }

# --- the fixture hive: $WORK/src/WT is a `.be/`-anchored worktree with a mounted
# sub DIR `test/` (so `//WT/test` stats dir) and a `dog.h` regular FILE (so
# `//WT/dog.h` stats reg).
SRC="$WORK/src"
mkdir -p "$SRC/WT/.be" "$SRC/WT/test/.be"
printf 'int dog;\n' > "$SRC/WT/dog.h"

SRC_ROOT="$SRC" "$JABC" "$_CASE/prevuri.js" "$PAGER" "$WHY" "$VIM" \
    >"$WORK/p.out" 2>"$WORK/p.err" || {
    echo "--- stderr ---"; cat "$WORK/p.err"; _fail "prevuri driver exited non-zero"; }
if grep -q '^FAIL' "$WORK/p.out"; then
    echo "--- driver out ---"; cat "$WORK/p.out"; _fail "prevuri check(s) failed"; fi
grep -q '^DONE' "$WORK/p.out" || { echo "--- driver out ---"; cat "$WORK/p.out"; _fail "prevuri driver did not finish"; }
echo "ok   pager stashes be.prev_uri; why/vim consume it, no welded arg (DIS-061)"

pass
