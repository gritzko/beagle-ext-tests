#!/bin/sh
# test/bro/barectx — DIS-061: a BARE `:verb` spell runs at the CONTEXT with no
# argument and NEVER scavenges a path off a rendered hunk banner.  The initial
# `status` view of a worktree with a mounted sub renders a `status test` banner
# whose relative, authority-less URI `test` was wrongly welded onto a bare
# `:diff` (→ `diff test`).  One headless leg over views/bro/pager.js, SKIP-
# guarded like the sibling pager cases.
. "$(dirname "$0")/../lib/brocase.sh"

PAGER="${PAGER_LIB:-$BROWT/views/bro/pager.js}"
[ -f "$PAGER" ] || { echo "barectx: SKIP — no views/bro/pager.js at $BROWT" >&2; pass; }

# SKIP if the jab build lacks the tty binding — the driver stubs tty.size.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.size === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo err)
[ "$HAS" = "yes" ] || { echo "barectx: SKIP — jab has no tty binding (got '$HAS')" >&2; pass; }

# --- the fixture: [/wiki/URI] steps 1-2 — `//WT` IS <project root>/work/WT,
# and the project root is DETECTED by the `.be` climb from the CWD.  $SRC_ROOT is
# read NOWHERE in the source (URI-016 retired srcRoot(); the old flat `$SRC_ROOT/WT`
# layout resolves to nothing).  brocase.sh already planted `$WORK/.be`, the TOPMOST
# anchor below $HOME, so $WORK IS the project root: seed its `work/` dir via
# the ONE helper and run the driver FROM INSIDE the worktree, so the climb lands
# on $WORK and `//WT/test` resolves + stats as a directory.  The driver still
# reads $SRC_ROOT, now purely as the fs path that HOSTS WT (= workRoot()), for its
# own file expectations — never as a product knob.
. "$_ROOT/lib/repo-setup.sh"
SRC=$(rs_work_root "$WORK")
mkdir -p "$SRC/WT/.be" "$SRC/WT/test/.be"

( cd "$SRC/WT" && SRC_ROOT="$SRC" "$JABC" "$_CASE/barectx.js" "$PAGER" ) \
        >"$WORK/b.out" 2>"$WORK/b.err" || {
    echo "--- stderr ---"; cat "$WORK/b.err"; _fail "barectx driver exited non-zero"; }
if grep -q '^FAIL' "$WORK/b.out"; then
    echo "--- driver out ---"; cat "$WORK/b.out"; _fail "barectx check(s) failed"; fi
grep -q '^DONE' "$WORK/b.out" || { echo "--- driver out ---"; cat "$WORK/b.out"; _fail "barectx driver did not finish"; }
echo "ok   pager bare :verb runs at context, no banner-scavenged arg (DIS-061)"

pass
