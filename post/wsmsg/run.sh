#!/bin/sh
# test/post/wsmsg — JAB-005 RED repro: a POST commit message with SPACES (and a
# `/`) must COMMIT with the message intact.  Under the RFC-strict URI grammar
# `new URI('fix URI/verb split')` THROWS `uri.parse: malformed`, and post.js
# parseSlots/isSlotArg ran EVERY positional arg through a bare `new URI` — so a
# normal multi-word commit message crashed before committing.  The fix: a total
# shared parse (shared/uri.js) — a non-URI arg is free-form message text, not a
# URI slot; verbs parse on entry and branch on the type.  SUT=loop; JS-ONLY.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/wsmsg
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (LAGS jab); alias BE=$JABC so the
# legacy `"$BE"` seeds run jab.
JABC=${JABC:-${JAB:-${BIN:+$BIN/jab}}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/wsmsg: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC"); BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "post/wsmsg: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export BE JABC BEDIR

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# Read the raw commit-object bytes at a worktree's trunk tip (the STORED message).
_commit_bytes() {   # _commit_bytes WTDIR
    cat > "$WORK/.cb.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const info=be.find(process.argv[2]);
const k=store.open(info.storePath,info.project);
const tip=k.resolveRef("");let out="";
if(tip){const c=k.getObject(tip);if(c)out=utf8.Decode(c.bytes);}
const u=utf8.Encode(out);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.cb.js" "$1" "$BEDIR" 2>/dev/null
}

# One case: fresh wt, baseline commit, stage a change, `jab post "$1"`, then
# assert the loop committed AND stored the message intact.  $2 = expected substr.
_check() {   # _check MSG EXPECT_SUBSTR LABEL
    _wt="$WORK/$3"; mkdir -p "$_wt/.be"
    ( cd "$_wt"
      printf 'A\n' > a.txt
      "$BE" post 'base' >/dev/null 2>&1 ) || _fail "[$3] baseline seed failed"
    ( cd "$_wt"
      sleep 0.02
      printf 'A2\n' > a.txt
      "$BE" put a.txt >/dev/null 2>&1 ) || _fail "[$3] stage failed"
    ( cd "$_wt" && "$JABC" post "$1" ) >"$WORK/$3.out" 2>"$WORK/$3.err" \
        || _fail "[$3] jab post '$1' FAILED (non-zero): $(cat "$WORK/$3.err")"
    grep -qE '^ *mod a\.txt' "$WORK/$3.out" \
        || _fail "[$3] jab post '$1' produced NO commit (silent drop): $(cat "$WORK/$3.out")"
    _cb=$(_commit_bytes "$_wt")
    printf '%s' "$_cb" | grep -qF "$2" \
        || _fail "[$3] commit message NOT stored intact (want '$2'); commit:
$_cb"
}

# THE BUG: a multi-word message with a `/` crashed `uri.parse: malformed`.
# Must now commit, message stored verbatim.
_check 'JAB-005: fix URI/verb split, allow spaces' 'JAB-005: fix URI/verb split, allow spaces' wsslash
echo "ok: whitespace+slash message commits with the message intact"

# CONTROL: a plain multi-word message (no punctuation) commits too.
_check 'fix the typo in readme' 'fix the typo in readme' plain
echo "ok: plain multi-word message commits"

echo "PASS [$NAME]"
