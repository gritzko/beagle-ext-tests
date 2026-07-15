#!/bin/sh
# test/post/colon-msg — JAB-003 RED repro: a POST commit message with a SECOND
# colon token (`TICKET: log: msg`) must COMMIT with the message intact.  Before
# the fix `cli()`→`resolve.seed`→`classifyArg` ran the message through `new URI`,
# splitting `TICKET: log: msg` into a MALFORMED path seed row (` log: msg`) →
# POST silently no-ops (rc=0, no commit).  A single-colon-with-space message
# (`TICKET: log msg`) escapes (valid URI) — so this case pins BOTH: the
# single-colon control still commits AND the double-colon message now commits,
# with the exact message (both colons) stored in the commit object.  SUT=loop
# (`jab post <msg>`, the resident dispatch); JS-ONLY.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/colon-msg
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (LAGS jab); alias BE=$JABC so the
# legacy `"$BE"` seeds run jab.
JABC=${JABC:-${JAB:-${BIN:+$BIN/jab}}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/colon-msg: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC"); BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "post/colon-msg: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export BE JABC BEDIR

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# Read the raw commit-object bytes at a worktree's trunk tip (so the assertion
# sees the STORED commit message, not just the banner) — the reader post.js uses.
_commit_bytes() {   # _commit_bytes WTDIR
    cat > "$WORK/.cb.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const info=be.treeAt(process.argv[2]);
const k=store.open(info.storePath,info.project);
const tip=k.resolveRef("");let out="";
if(tip){const c=k.getObject(tip);if(c)out=utf8.Decode(c.bytes);}
const u=utf8.Encode(out);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.cb.js" "$1" "$BEDIR" 2>/dev/null
}

# One case: fresh wt, baseline commit, stage a change, `jab post "$1"`, then
# assert the loop committed AND stored the message intact.  $2 = the expected
# message substring that MUST appear in the commit object.
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
    # the loop must have committed: a `mod a.txt` per-file row in the banner.
    grep -qE '^ *mod a\.txt' "$WORK/$3.out" \
        || _fail "[$3] jab post '$1' produced NO commit (silent drop): $(cat "$WORK/$3.out")"
    # the STORED commit object must carry the message with EVERY colon intact.
    _cb=$(_commit_bytes "$_wt")
    printf '%s' "$_cb" | grep -qF "$2" \
        || _fail "[$3] commit message NOT stored intact (want '$2'); commit:
$_cb"
}

# CONTROL: a single-colon-with-space message escapes today (valid URI) — commits.
_check 'JAB-003: log msg' 'JAB-003: log msg' single
echo "ok: single-colon message commits with the message intact"

# THE BUG: a SECOND colon token was URI-split into a malformed path → silent
# no-op.  Must now commit, message (both colons) stored verbatim.
_check 'JAB-003: log: msg' 'JAB-003: log: msg' double
echo "ok: double-colon message commits with both colons intact"

echo "PASS [$NAME]"
