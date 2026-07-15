#!/bin/sh
# test/bro/context — BRO-024: the pager context URI is REDUCED to `//WT/dir`
# (the nav $PWD; ?rev/#hash never enter it), the address bar renders the
# prompt-like invite `//WT/dir/: <spell>`, `..` clamps at the worktree root,
# and a deleted context dir paints the invite red.  One headless leg over the
# worktree's views/bro/pager.js; SKIP-guarded like the sibling pager cases.
. "$(dirname "$0")/../lib/brocase.sh"

PAGER="${PAGER_LIB:-$BROWT/views/bro/pager.js}"
[ -f "$PAGER" ] || { echo "context: SKIP — no views/bro/pager.js at $BROWT" >&2; pass; }

# SKIP if the jab build lacks the tty binding — the pager driver stubs tty.size.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.size === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo err)
[ "$HAS" = "yes" ] || { echo "context: SKIP — jab has no tty binding (got '$HAS')" >&2; pass; }

# --- the fixture: [/wiki/URI] steps 1-2 — `//WT` IS <project root>/work/WT,
# and the project root is DETECTED by the `.be` climb from the CWD.  $SRC_ROOT is
# read NOWHERE in the source (URI-016 retired srcRoot(); the old flat `$SRC_ROOT/WT`
# layout resolves to nothing).  brocase.sh already planted `$WORK/.be`, the TOPMOST
# anchor below $HOME, so $WORK IS the project root: seed its `work/` dir via
# the ONE helper and run the driver FROM INSIDE the worktree, so the climb lands
# on $WORK and `//WT/dog/DOG.h` resolves + stats through discover.  The driver
# still reads $SRC_ROOT, now purely as the fs path that HOSTS WT (= workRoot()),
# for its own file expectations — never as a product knob.
. "$_ROOT/lib/repo-setup.sh"
SRC=$(rs_work_root "$WORK")
mkdir -p "$SRC/WT/.be" "$SRC/WT/dog"
: > "$SRC/WT/dog/DOG.h"

( cd "$SRC/WT" && SRC_ROOT="$SRC" "$JABC" "$_CASE/context.js" "$PAGER" ) \
        >"$WORK/c.out" 2>"$WORK/c.err" || {
    echo "--- stderr ---"; cat "$WORK/c.err"; _fail "context driver exited non-zero"; }
if grep -q '^FAIL' "$WORK/c.out"; then
    echo "--- driver out ---"; cat "$WORK/c.out"; _fail "context check(s) failed"; fi
grep -q '^DONE' "$WORK/c.out" || { echo "--- driver out ---"; cat "$WORK/c.out"; _fail "context driver did not finish"; }
echo "ok   pager context reduction + invite + clamp + red (BRO-024)"

pass
