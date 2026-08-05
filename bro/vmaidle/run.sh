#!/bin/sh
# test/bro/vmaidle — BRO-046: an IDLE pager must cost ZERO file mappings.
# The 100 ms key-wait spin re-derives the ci badge every pass; the badge's
# `contextWt` paid two uncached `.be` climbs, each one an mmap nothing unmaps,
# so a pager left alone grew ~19 VMAs/s and died at vm.max_map_count in ~57 min.
# idlevma.py runs the FULL pager on a pty (the bro/ci kin), types NOTHING, and
# counts /proc/<pid>/maps over an idle window: RED = strictly growing, GREEN =
# flat.  Registered by the be/test glob as be-js-bro-vmaidle.
. "$(dirname "$0")/../lib/brocase.sh"

[ -f "$BROWT/views/bro/pager.js" ] || { echo "bro/vmaidle: SKIP — no pager at $BROWT" >&2; pass; }
[ -f "$BROWT/shared/ci.js" ]       || { echo "bro/vmaidle: SKIP — no shared/ci.js at $BROWT" >&2; pass; }

command -v python3 >/dev/null 2>&1 || { echo "bro/vmaidle: SKIP — no python3" >&2; pass; }
python3 -c "import pty,select" 2>/dev/null || { echo "bro/vmaidle: SKIP — no pty module" >&2; pass; }
# The whole assertion is a VMA census, which only /proc gives us.
[ -r "/proc/self/maps" ] || { echo "bro/vmaidle: SKIP — no /proc/<pid>/maps" >&2; pass; }

# SKIP if the jab build lacks the tty binding (pre-JS-053) — the pager is blocked.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.raw === "function" &&
           typeof tty.openpty === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo err)
[ "$HAS" = "yes" ] || { echo "bro/vmaidle: SKIP — jab has no tty binding (got '$HAS')" >&2; pass; }

# --- the fixture worktree (the bro/ci shape) -------------------------------
. "$_ROOT/lib/repo-setup.sh"
SRC="$WORK/src"
WORKD=$(rs_work_root "$SRC")
ln -sfn "$BROWT" "$SRC/jsrc"
BE_ROOT="$WORK"; export BE_ROOT
FIX="$WORKD/IDLE"
mkdir -p "$FIX/.be"
printf 'alpha\n' > "$FIX/hello.txt"
( cd "$FIX" && "$JABC" post '#seed' ) >"$WORK/seed.out" 2>"$WORK/seed.err" || {
    echo "--- seed stderr ---"; cat "$WORK/seed.err"; _fail "fixture post failed"; }

# No CI run is started here, so the badge stays "" — the leak is the RESOLUTION
# behind it, which the spin pays whether or not anything is running.
CITMP="$WORK/citmp"; mkdir -p "$CITMP"

TMP="$CITMP" python3 "$_CASE/idlevma.py" "$JABC" "$FIX" >"$WORK/v.out" 2>"$WORK/v.err" || {
    echo "--- stderr ---"; cat "$WORK/v.err"
    echo "--- out ---";    cat "$WORK/v.out"; _fail "idle pager leaks file mappings"; }
grep -q '^DONE' "$WORK/v.out" || { echo "--- out ---"; cat "$WORK/v.out"; _fail "idle probe did not finish"; }
sed 's/^/     /' "$WORK/v.out"
echo "ok   an idle pager's mapping count stays flat"
pass
