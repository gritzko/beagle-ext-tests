#!/bin/sh
# test/commit/ticket — COMMIT-007: `be/views/commit/commit.js` must (1) render the
# author/committer date in HUMAN form (the lib's short `ron.date`, as `log:` does),
# not the raw git `<epoch> <tz>`; and (2) fuse an issue key (`ABC-123`) in the
# message into an `F` token carrying a hidden `U` ticket-file click-target, reusing
# BRO-012's shared shared/ticket.js resolver (todo/<TOPIC>/<KEY>.{mkd,md,txt} under
# a be.todoRoot() root).  RED before the fix: the date field shows a bare 10-digit
# epoch and the ticket code is flat text (no F, no U).  GREEN after.
#
# JAB-ONLY (no native parity): the human date DELIBERATELY diverges from C `be`
# (which prints the raw epoch) — a SPEC deviation (COMMIT-007), so we assert jab's
# own --tlv stream via the pager's hunksFromTlv + _uriAt, never against `be`.
# `be post` is used ONLY as the store writer to seed the fixture commit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/commit/ticket
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (it LAGS jab); locate jab and
# alias BE=$JABC so legacy `"$BE" post/put` seeds run jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "commit/ticket: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "commit/ticket: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/shared/ticket.js" ] || { echo "commit/ticket: SKIP — no shared/ticket.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "commit/ticket: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/commit/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink so bareword `jab commit`
# resolves the extension via jab's upward be/-scan from the worktree cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# The fixture ticket tree ($TODO_ROOT): a real todo/<TOPIC>/<KEY>.mkd file so the
# resolver has a hit; and a commit whose SUBJECT cites that key.
CODE=ABC-123
TODO="$WORK/todo_root"
mkdir -p "$TODO/todo/ABC"
printf '#   %s: fixture ticket\nbody\n' "$CODE" > "$TODO/todo/ABC/$CODE.mkd"

WT="$WORK/wt"; mkdir -p "$WT/.be"
cd "$WT"
printf 'x\n' > a.txt
"$BE" post "fix $CODE in the parser" >/dev/null 2>&1 || _fail "be post (fixture commit)"

# The tip commit's full 40-hex sha (resolvable).
SHA=$("$JABC" "$_ROOT/put/tipsha.js" "$WT")
[ -n "$SHA" ] || _fail "could not resolve the tip sha"
case "$SHA" in *[!0-9a-f]*|"") _fail "tip sha not 40-hex: '$SHA'" ;; esac

# --plain must (a) show a HUMAN date, no bare 10-digit epoch, and (b) NOT leak
# the hidden ticket URI bytes (plain stays U-free, COMMIT-003).
( cd "$WT" && TODO_ROOT="$TODO" "$JABC" commit "commit:?$SHA" --plain ) \
    >"$WORK/jab.plain" 2>"$WORK/jab.err" \
    || _fail "jab commit --plain failed ($(cat "$WORK/jab.err"))"
[ -s "$WORK/jab.plain" ] || _fail "jab commit --plain emitted ZERO bytes"
grep -qE '^(author|committer) .*[0-9]{10} [+-][0-9]{4}[[:space:]]*$' "$WORK/jab.plain" \
    && _fail "the author/committer line still shows a raw 10-digit epoch"
grep -qE 'cat:|:\?|[[:space:]]\?[0-9a-f]{40}' "$WORK/jab.plain" \
    && _fail "hidden ticket/U URI bytes leaked into --plain output"
echo "ok: --plain shows a human date, no raw epoch, no hidden URI leak"

# --tlv: capture the on-wire HUNK stream and assert (via the pager) the message
# `F`+hidden-`U` ticket target AND the human-date field.  RED pre-fix, GREEN post.
( cd "$WT" && TODO_ROOT="$TODO" "$JABC" commit "commit:?$SHA" --tlv ) \
    >"$WORK/jab.tlv" 2>"$WORK/jab.err2" \
    || _fail "jab commit --tlv failed ($(cat "$WORK/jab.err2"))"
[ -s "$WORK/jab.tlv" ] || _fail "jab commit --tlv emitted ZERO bytes"

# The expected ticket URI carries the fixture root's `//name` + the todo path.
TODO_ROOT="$TODO" "$JABC" "$_CASE/check.js" "$WORK/jab.tlv" "$CODE" \
    >"$WORK/check.out" 2>&1 \
    || { cat "$WORK/check.out" >&2; _fail "ticket/date assertions failed"; }
grep -q "test/commit/ticket OK" "$WORK/check.out" \
    || { cat "$WORK/check.out" >&2; _fail "check.js did not report OK"; }
echo "ok: message $CODE → F token + hidden U ticket URI (_uriAt), human date"

echo "PASS [$NAME]"
