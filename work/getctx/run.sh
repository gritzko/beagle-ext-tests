#!/bin/sh
# test/work/getctx — WORK-002: a work-view [get] O-invite mutates the ROW's
# worktree, never the LAUNCH tree.  Live incident: [get] on the //bro-why row
# appended `get ///be#...` to the LAUNCH tree's .be (work/WORK-001), re-pinning
# its track; the row's wt stayed untouched.  FIXTURE: a project root META with
# mount vend/ext (2 commits), work/PIN-1 + work/PIN-2 tracking the vend/ext
# WORKTREE at commit 1 (behind), work/BASE a real trunk clone of the SAME
# shard (related ancestry — the incident's launch shape).  getctx.py runs the
# FULL `jab work` pager on a pty (pty.fork) from BASE and clicks the buttons
# with real SGR mouse bytes.  RED before the WORK-002 fix: BASE/.be gains the
# `get ///vend/ext#<tip>` row and PIN-1 gets nothing.  GREEN: PIN-1/.be gains
# the row, BASE/.be and META's wtlog stay byte-identical.  Also: [diff] on the
# row must not err, and a [get] whose context wt was REMOVED under it must
# refuse loudly (no cwd fallback — the NAVESCAPE spirit).
# Registered by the be/test glob as be-js-work-getctx — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/work/getctx
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "work/getctx: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "work/getctx: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

# The pty harness needs python3 with the pty module (the universal/pager.py kin).
command -v python3 >/dev/null 2>&1 || { echo "work/getctx: SKIP — no python3" >&2; exit 0; }
python3 -c "import pty,select" 2>/dev/null || { echo "work/getctx: SKIP — no pty module" >&2; exit 0; }

: "${TMP:=/tmp}"; export TMP
NAME=getctx
WORK="$TMP/$$/work/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the jsrc symlink (barewords resolve via jab's upward
# jsrc/-scan from the fixture cwd).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [work/$NAME] $*" >&2; exit 1; }
_sha40() { grep -o '[0-9a-f]\{40\}' "$1" | sed -n "$2p"; }

# --- the FIXTURE forest (the test/work/view shapes) --------------------------
META="$WORK/meta"
mkdir -p "$META/.be" "$META/vend/ext/.be"
cat > "$META/.gitmodules" <<'EOF'
[submodule "ext"]
	path = vend/ext
	url = git@github.com:nowhere/extproj.git
EOF
# Seed ext FIRST, then META — the root post then records the vend/ext mount as
# a de-jure gitlink pin (at ext's tip), which `get ///vend/ext` resolves via.
( cd "$META/vend/ext" && printf 'e1\n' > e.txt && "$BE" post 'ext one' ) \
    >/dev/null 2>&1 || _fail "seed ext one"
( cd "$META/vend/ext" && printf 'e2\n' >> e.txt && "$BE" post 'ext two' ) \
    >/dev/null 2>&1 || _fail "seed ext two"
( cd "$META" && printf 'root\n' > R.txt && "$BE" put vend/ext \
  && "$BE" post 'root commit' ) \
    >/dev/null 2>&1 || _fail "seed root post"
SHA1=$(_sha40 "$META/vend/ext/.be/wtlog" 1)          # ext one
SHA2=$(_sha40 "$META/vend/ext/.be/wtlog" 2)          # ext two
[ -n "$SHA1" ] && [ -n "$SHA2" ] || _fail "sha capture"
printf '26718JF48j\tpost\t?#%s\n26718JF49f\tpost\t?#%s\n' \
    "$SHA1" "$SHA2" > "$META/vend/ext/.be/refs"

# PIN-1/PIN-2: track the vend/ext WORKTREE (URI-shaped), based at SHA1 (behind).
for P in PIN-1 PIN-2; do
    mkdir -p "$META/work/$P"
    printf '26718JG001\tget\tfile:%s/vend/ext/.be/?\n26718JG002\tget\t///vend/ext#%s\n' \
        "$META" "$SHA1" > "$META/work/$P/.be"
done
# BASE: the LAUNCH tree — a REAL trunk clone off the SAME shard (related
# ancestry, so a wrong-tree get would re-pin it exactly like the incident).
mkdir -p "$META/work/BASE"
( cd "$META/work/BASE" && "$BE" get "file:$META/vend/ext/.be?" ) \
    >/dev/null 2>&1 || _fail "BASE clone"
grep -q "$SHA2" "$META/work/BASE/.be" || _fail "BASE clone not at trunk"

# --- snapshots, then the pty click sessions (cwd = BASE, the launch tree) ----
cp "$META/.be/wtlog" "$WORK/meta.wtlog.before"
cp "$META/work/BASE/.be" "$WORK/base.be.before"
grep -q "get	///vend/ext#$SHA2" "$META/work/PIN-1/.be" && _fail "fixture PIN-1 already at tip"

python3 "$_CASE/getctx.py" "$JABC" "$META/work/BASE" "$META/work" \
    > "$WORK/py.out" 2>"$WORK/py.err" \
    || { cat "$WORK/py.out" "$WORK/py.err" >&2; _fail "pty sessions failed"; }
grep -q "getctx sessions done" "$WORK/py.out" \
    || { cat "$WORK/py.out" >&2; _fail "pty driver did not finish"; }

# --- assertions --------------------------------------------------------------
# 1. THE bug: the [get] mutation lands in the ROW's wt (PIN-1), tip row appended.
GETROWS=$(grep -c "get	///vend/ext#$SHA2" "$META/work/PIN-1/.be" || true)
[ "$GETROWS" = "1" ] \
    || { cat "$WORK/py.out" >&2; \
         _fail "[get] did not land in PIN-1 (rows at tip: $GETROWS) — ran in the launch tree?"; }
# 2. The LAUNCH tree's .be is byte-identical (the incident's damage shape) —
#    covers R1's view click, R2's refused mutation AND R3's context'd get.
cmp -s "$WORK/base.be.before" "$META/work/BASE/.be" \
    || { diff "$WORK/base.be.before" "$META/work/BASE/.be" >&2 || true; \
         _fail "a click mutated the LAUNCH tree's .be (the WORK-002 incident)"; }
# 3. The project root stays untouched too.
cmp -s "$WORK/meta.wtlog.before" "$META/.be/wtlog" || _fail "a click mutated META's wtlog"

echo "PASS [work/$NAME]"
