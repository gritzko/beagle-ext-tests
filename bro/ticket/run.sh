#!/bin/sh
# test/bro/ticket — BRO-012: one-click ticket codes.  An `F` issue-key token in
# a file body opens its `todo/<TOPIC>/<KEY>.mkd` ticket file (the pager derives
# the target from the token TEXT, no producer U); a ticket code in a `log:`
# commit summary is split into S/F/S with a hidden `U` ticket URI spliced in, so
# it is clickable via the SAME _uriAt path.  Both converge on shared/ticket.js,
# which owns the ROOT ORDER via be.todoRoot(): $TODO_ROOT env > current wt root
# > open/launch wt root; the first whose todo/<TOPIC>/<KEY>.<ext> exists wins.
#
# RED before the fix: a body F had no U → _uriAt returned null (dead link); a
# summary code was one flat S span (no F/U) → a click returned null.  Also RED
# if the resolver ignores be.todoRoot()'s order (env / current / open).  GREEN
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

# THREE sibling worktrees under SRC_ROOT, each holding the SAME ticket at the
# todo/<TOPIC>/<KEY>.mkd layout — so the resolved URI's `//name` reveals which
# root be.todoRoot() picked (env > current > open).  The `be ->` shard symlink
# lets jab resolve the be/ extension by scanning up from SRC_ROOT.
CODE=ABC-123
SRC="$WORK/src"
mkdir -p "$SRC"
ln -sfn "$BEDIR" "$SRC/jsrc"
for t in envtree curtree opentree; do
  mkdir -p "$SRC/$t/.be" "$SRC/$t/todo/ABC"
  printf '#   %s: fixture ticket in %s\nbody\n' "$CODE" "$t" > "$SRC/$t/todo/ABC/$CODE.mkd"
done
export SRC_ROOT="$SRC"
# TEST-003: CONFINE discovery to the sibling-tree root.  navCwd/topWt name a tree
# by climbing to the OUTERMOST `.be` anchor below $HOME; a repo-setup firewall at
# dirname($TMP) would make topWt overshoot SRC_ROOT (naming //tmp not //envtree).
# Setting HOME=$SRC stops the walk AT the sibling trees, so `//<tree>` resolves.
export HOME="$SRC"

# The log-view fixture lives in the OPEN/launch tree (opentree): a commit whose
# SUMMARY carries the ticket code.  Built with `be post` exactly like
# test/bro/rowclick — the CODE UNDER TEST is jab (log: producer + the pager),
# not the store writer.
cd "$SRC/opentree"
printf 'one\n' > a.txt
"$BE" post "fix $CODE in the parser" >/dev/null 2>&1 || _fail "be post (fixture commit)"
# Capture the JS loop's log: --tlv (the log-view producer under test) — with
# TODO_ROOT set so the summary `F`+`U` splice resolves to the env tree.
TODO_ROOT="$SRC/envtree" "$JABC" log: --tlv >"$WORK/jab.tlv" 2>"$WORK/jab.err" \
    || _fail "jab log: --tlv failed ($(cat "$WORK/jab.err"))"
[ -s "$WORK/jab.tlv" ] || _fail "jab log: --tlv emitted ZERO bytes"

# The cat-view fixture: a .mkd body carrying the code (the grammar that FUSES it
# into an F), cat'd through the REAL producer (views/cat withLinks, which
# blankets every word with a grep: click-target).  BRO-012 must make the F token
# link to the TICKET, not that grep spell — the reported cat-view bug.
printf 'see %s now\n' "$CODE" > note.mkd
TODO_ROOT="$SRC/envtree" "$JABC" cat:note.mkd --tlv >"$WORK/cat.tlv" 2>"$WORK/cat.err" \
    || _fail "jab cat:note.mkd --tlv failed ($(cat "$WORK/cat.err"))"
[ -s "$WORK/cat.tlv" ] || _fail "jab cat: --tlv emitted ZERO bytes"

# ---- (a) $TODO_ROOT env WINS: resolver picks //envtree (+ the cat-view case) --
TODO_ROOT="$SRC/envtree" "$JABC" "$_CASE/check.js" \
    "$SRC" "$WORK/jab.tlv" "$CODE" env envtree "$WORK/cat.tlv" >"$WORK/env.out" 2>&1 \
    || { cat "$WORK/env.out" >&2; _fail "TODO_ROOT-env precedence assertions failed"; }
grep -q "test/bro/ticket OK" "$WORK/env.out" || { cat "$WORK/env.out" >&2; _fail "env case: no OK"; }

# ---- (b) env UNSET: the CURRENT wt root (curtree) wins ------------------------
"$JABC" "$_CASE/check.js" \
    "$SRC" "$WORK/jab.tlv" "$CODE" current curtree >"$WORK/cur.out" 2>&1 \
    || { cat "$WORK/cur.out" >&2; _fail "current-wt precedence assertions failed"; }
grep -q "test/bro/ticket OK" "$WORK/cur.out" || { cat "$WORK/cur.out" >&2; _fail "current case: no OK"; }

# ---- (c) env unset + current MISSING: fall through to open/launch (opentree) --
rm -f "$SRC/curtree/todo/ABC/$CODE.mkd"
"$JABC" "$_CASE/check.js" \
    "$SRC" "$WORK/jab.tlv" "$CODE" open opentree >"$WORK/open.out" 2>&1 \
    || { cat "$WORK/open.out" >&2; _fail "open-wt fall-through assertions failed"; }
grep -q "test/bro/ticket OK" "$WORK/open.out" || { cat "$WORK/open.out" >&2; _fail "open case: no OK"; }

echo "PASS [bro/$NAME]"
