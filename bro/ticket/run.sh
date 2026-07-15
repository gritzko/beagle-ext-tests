#!/bin/sh
# test/bro/ticket — BRO-012: one-click ticket codes.  An `F` issue-key token in
# a file body opens its `todo/<TOPIC>/<KEY>.mkd` ticket file (the pager derives
# the target from the token TEXT, no producer U); a ticket code in a `log:`
# commit summary is split into S/F/S with a hidden `U` ticket URI spliced in, so
# it is clickable via the SAME _uriAt path.  Both converge on shared/ticket.js.
#
# URI-016: there is no root ORDER left to test.  be.todoRoot() IS
# `projectRoot()+"/todo"` — ONE tree, at the DETECTED project root ("project
# root CAN NOT BE AN ENV VAR; it is detected by a climb").  The old three-tier
# ($TODO_ROOT env > current wt > open/launch wt) precedence ladder is GONE, so
# the fixture is one project root carrying `todo/` + one worktree to run from, and
# a ticket URI always carries the project root's bare `//` authority.
#
# RED before the fix: a body F had no U → _uriAt returned null (dead link); a
# summary code was one flat S span (no F/U) → a click returned null.  GREEN
# after.  Registered by the be/test glob as be-js-bro-ticket — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/bro/ticket
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (it now LAGS jab).  Locate jab and
# alias BE=$JABC so the legacy `"$BE" post` fixture commit runs jab too.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "bro/ticket: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "bro/ticket: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/views/bro/pager.js" ] || { echo "bro/ticket: SKIP — no pager.js" >&2; exit 0; }
[ -f "$BEDIR/shared/ticket.js" ] || { echo "bro/ticket: SKIP — no shared/ticket.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "bro/ticket: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=ticket
WORK="$TMP/$$/bro/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [bro/$NAME] $*" >&2; exit 1; }

# tty-binding probe (the pager needs tty for width); SKIP cleanly if absent.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.size === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo no)
[ "$HAS" = "yes" ] || { echo "bro/ticket: SKIP — jab has no tty binding" >&2; exit 0; }

# URI-016: ONE ticket tree, at the PROJECT ROOT — be.todoRoot() is
# `projectRoot()+"/todo"`, so `$SRC/todo/<TOPIC>/<KEY>.mkd` is the only place a
# ticket can live, and every resolved URI carries the project root's bare `//`
# authority (navCwd(projectRoot()) has no `//name`).  rs_work_root seeds $SRC's
# `.be` anchor (what the climb detects) + its `work/` dir; the single worktree
# below is just somewhere to run jab FROM.  The `jsrc ->` shard symlink at $SRC
# lets jab resolve the extension by scanning up from the worktree.
CODE=ABC-123
SRC="$WORK/src"
. "$_ROOT/lib/repo-setup.sh"
WORKD=$(rs_work_root "$SRC")
ln -sfn "$BEDIR" "$SRC/jsrc"
mkdir -p "$SRC/todo/ABC"
printf '#   %s: fixture ticket\nbody\n' "$CODE" > "$SRC/todo/ABC/$CODE.mkd"
mkdir -p "$WORKD/wt/.be"
# TEST-003/URI-016: CONFINE discovery ABOVE the work/ dir.  The project climb keeps
# the TOPMOST `.be` anchor below $BE_ROOT, so $BE_ROOT must sit ABOVE $SRC (it
# would otherwise cut the climb short of the project root).  Was `HOME=$SRC`,
# which now BOTH loses to the ctest-set $BE_ROOT and points at the wrong level.
export BE_ROOT="$WORK"

# The log-view fixture lives in the worktree we launch from: a commit whose SUMMARY
# carries the ticket code.  Built with `be post` exactly like test/bro/rowclick
# — the CODE UNDER TEST is jab (log: producer + the pager), not the store writer.
cd "$WORKD/wt"
printf 'one\n' > a.txt
"$BE" post "fix $CODE in the parser" >/dev/null 2>&1 || _fail "be post (fixture commit)"
# Capture the JS loop's log: --tlv (the log-view producer under test); the
# summary `F`+`U` splice resolves against the climbed project root ($SRC).
"$JABC" log: --tlv >"$WORK/jab.tlv" 2>"$WORK/jab.err" \
    || _fail "jab log: --tlv failed ($(cat "$WORK/jab.err"))"
[ -s "$WORK/jab.tlv" ] || _fail "jab log: --tlv emitted ZERO bytes"

# The cat-view fixture: a .mkd body carrying the code (the grammar that FUSES it
# into an F), cat'd through the REAL producer (views/cat withLinks, which
# blankets every word with a grep: click-target).  BRO-012 must make the F token
# link to the TICKET, not that grep spell — the reported cat-view bug.
printf 'see %s now\n' "$CODE" > note.mkd
"$JABC" cat:note.mkd --tlv >"$WORK/cat.tlv" 2>"$WORK/cat.err" \
    || _fail "jab cat:note.mkd --tlv failed ($(cat "$WORK/cat.err"))"
[ -s "$WORK/cat.tlv" ] || _fail "jab cat: --tlv emitted ZERO bytes"

# ---- the resolver finds the ONE ticket tree at the climbed project root ------
# URI-016: the old (a)/(b)/(c) precedence legs ($TODO_ROOT env > current wt >
# open/launch wt) are DELETED — that ladder no longer exists.  One run covers
# the body-F click, the log-summary F+U splice, and the cat-view case.
"$JABC" "$_CASE/check.js" \
    "$SRC" "$WORK/jab.tlv" "$CODE" "$WORK/cat.tlv" >"$WORK/check.out" 2>&1 \
    || { cat "$WORK/check.out" >&2; _fail "ticket resolver assertions failed"; }
grep -q "test/bro/ticket OK" "$WORK/check.out" || { cat "$WORK/check.out" >&2; _fail "no OK"; }

echo "PASS [bro/$NAME]"
