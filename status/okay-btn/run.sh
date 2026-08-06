#!/bin/sh
# test/status/okay-btn — a CONFLICTED status row carries an `[okay]` button that
# does exactly what `[put]` does: it stages that path's CURRENT bytes as the
# resolution (gritzko's order, 2026-08-04).
#
# Post-[/todo/DIS/DIS-080] conflicts are MARKERLESS: the get-merge writes the RGA
# live reading (both sides' tokens, no `<<<<` fences), the user edits the woven
# bytes, and accepting what is there IS the resolution — a `put <path>` row LATER
# than the `con` row acks it (wtlog.conflicts(), DIS-080 §4).  `[okay]` is that
# acceptance in one click.  It rides the BE-041 button table in views/status/
# status.js exactly like `[put]`/`[del]`: a VISIBLE label token followed by the
# hidden `O` click spell `put <wt-relative-path>` — RAW, no //authority, no
# pre-resolution (BE-039: the VERB resolves, the pager stays arg-blind).
#
# Driven through the REAL UI path (memory rule: no tlv-only acceptance for a
# pager change).  run.sh builds the conflict and checks the PLAIN parity; okay.py
# forks a pty, execs the real `jab status` in it (isatty(1) -> the universal bro
# pager, JAB-030), reads the painted frame, clicks the `[okay]` cell and asserts
# the row FLIPS to staged and the wtlog grew the `put` row.
#
#       T0 ── (feat: F1 sets line2=X)      cur switches trunk->feat->trunk
#  wt on trunk T0, dirty edit line2=Y, then `get ?#F1` weave-merges feat in:
#  ours(Y) vs theirs(X) diverge on the same anchor -> `con f.txt`.  The fixture
#  then HAND-EDITS the weave (the resolution the user types); per [/todo/STATUS/
#  STATUS-017] that keeps the row `...!` — only a put/post resolves it.
#
# KNOWN HOLE (reported, not fixed here): on a PRISTINE weave — the merge output
# accepted with no edit at all — `put <path>` refuses with "put: nothing to
# stage", because shared/stage.js classifyNamed takes the get/post mtime-stamp
# fast path ("is unchanged") on bytes the merge itself wrote.  Same family as
# [/todo/PUT/PUT-016] (patched-in files are DIRTY and put must stage them).  The
# button mints the ordered spell either way; this fixture edits the weave first,
# which is the flow the order describes.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/status/okay-btn
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (it LAGS jab); locate jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "status/okay-btn: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "status/okay-btn: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/views/bro/pager.js" ] || { echo "status/okay-btn: SKIP — no pager.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

# The driver is a controlling-terminal harness (the test/todo/click model).
command -v python3 >/dev/null 2>&1 || { echo "status/okay-btn: SKIP — no python3" >&2; exit 0; }
python3 -c "import pty,select,fcntl,termios" 2>/dev/null \
    || { echo "status/okay-btn: SKIP — no pty module" >&2; exit 0; }

#  Pin the clock so the weave's RGA tie-break side order is reproducible run to
#  run (a TEST artifact, not a merge bug) — the status/conflict idiom.
: "${SOURCE_DATE_EPOCH:=1467331200}"; export SOURCE_DATE_EPOCH   # 2016-07-01Z
: "${TZ:=UTC}"; export TZ

: "${TMP:=/tmp}"; export TMP
NAME=okay-btn
WORK="$TMP/$$/status/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall: an empty `.be` FILE above the scratch base stops a cwd-walk
# from escaping to a real $HOME/.be (rs firewall, DIS-024).
: > "$TMP/$$/.be" 2>/dev/null || true
# JS verbs run bareword (`jab status`); jab's upward be/-scan resolves the
# extension via this `jsrc` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [status/$NAME] $*" >&2; exit 1; }
# jab is ASAN — drop the rolling keeper.idx before each op so an earlier commit's
# fork-point object stays visible after a later post (patchcase.sh idiom).
_jab() { rm -f "$WT"/.be/*/*.keeper.idx 2>/dev/null || true; ( cd "$WT" && "$BE" "$@" ); }

# SKIP if the jab build lacks the tty binding (pre-JS-053: no pager at all).
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.size === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo no)
[ "$HAS" = "yes" ] || { echo "status/okay-btn: SKIP — jab has no tty binding" >&2; exit 0; }

# --- the fixture: one conflicted row, one mod row, one clean file ------------
WT="$WORK/wt"; mkdir -p "$WT/.be"
printf 'a\nb\nc\n' > "$WT/f.txt"          # -> con  (the [okay] row)
printf 'M\n'       > "$WT/mod.txt"        # -> mod  (keeps [put])
printf 'OK\n'      > "$WT/ok.txt"         # -> ok   (no row at all, no button)
_jab post 't0' >/dev/null 2>&1 || _fail "could not seed t0"
# DIS-076: a bare post never mints a ref — read the wt's OWN cur tip.
BOOT=$("$JABC" "$_ROOT/put/tipsha.js" "$WT")
[ -n "$BOOT" ] || _fail "no trunk tip"

# feat = fork at T0, switch, F1 sets line2=X, back to trunk.
_jab put '?feat'   >/dev/null 2>&1 || _fail "fork feat"
_jab get '?feat'   >/dev/null 2>&1 || _fail "switch feat"
printf 'a\nX\nc\n' > "$WT/f.txt"
_jab put f.txt     >/dev/null 2>&1 || _fail "stage f1"
_jab post 'f1 line2=X' >/dev/null 2>&1 || _fail "commit f1"
F1=$("$JABC" "$_ROOT/put/tipsha.js" "$WT")
[ -n "$F1" ] || _fail "no feat tip"
_jab get "?#$BOOT" >/dev/null 2>&1 || _fail "switch back to trunk"

# dirty edit on trunk (line2=Y) + an ordinary mod, then get-merge feat F1.
printf 'a\nY\nc\n' > "$WT/f.txt"
printf 'M2\n'      > "$WT/mod.txt"
_jab get "?#$F1"   >/dev/null 2>&1 || true        # CONFMARK -> non-zero, ignore

grep -q '<<<<' "$WT/f.txt" && _fail "conflict fences written by the get-merge" || true
grep -a "$(printf '\tcon\t')" "$WT/.be/wtlog" 2>/dev/null | grep -q 'f\.txt' \
    || _fail "no durable 'con f.txt' row in the wtlog"

# STATUS-017: the user edits the woven bytes — the resolution they intend.  The
# row STAYS `...!` (liveness is the con ROW, not the bytes); the edit is also
# what lifts the merge's own mtime stamp, so the `put` the button mints has
# something to stage (see the KNOWN HOLE above).
sleep 0.02
printf 'a\nXY\nc\n' > "$WT/f.txt"

_bucket() { ( cd "$WT" && "$JABC" status --plain 2>/dev/null ) \
    | sed -nE "s/^.{8}\.\.\.(.) $1\$/\1/p" | head -1; }
[ "$(_bucket f.txt)" = "!" ] || _fail "f.txt is not conflicted (wt char '$(_bucket f.txt)', want '!')"
[ "$(_bucket mod.txt)" = "v" ] || _fail "mod.txt is not a plain mod (wt char '$(_bucket mod.txt)')"
echo "     ok   fixture-con-and-mod   (f.txt '...!', mod.txt '...v', ok.txt clean)"

# --- 1. PLAIN parity: buttons are pager-only chrome -------------------------
# The non-tty path must not grow a byte: `[okay]` never reaches `| cat`, exactly
# as `[put]`/`[del]` never do (test/status/buttons leg 1).
( cd "$WT" && "$JABC" status --plain ) >"$WORK/plain" 2>/dev/null || true
[ -s "$WORK/plain" ] || _fail "jab status --plain emitted ZERO bytes"
sed -E 's/^.{8}([.xovXOV!]{4}) /\1 /' "$WORK/plain" >"$WORK/plain.norm"
printf 'status\n...! f.txt\n...v mod.txt\n?\t2 wt, 1 con\n' >"$WORK/plain.golden"
cmp -s "$WORK/plain.norm" "$WORK/plain.golden" || {
    echo "--- jab --plain (date-normalised) ---"; cat -A "$WORK/plain.norm"
    echo "--- golden ---";                        cat -A "$WORK/plain.golden"
    _fail "plain output diverged"; }
grep -Fq '[okay]' "$WORK/plain" && _fail "plain output leaks the [okay] label" || true
grep -Fq '[put]'  "$WORK/plain" && _fail "plain output leaks the [put] label"  || true
echo "     ok   plain-parity          (no button labels on the non-tty path)"

# --- 2. the pty click -------------------------------------------------------
rm -f "$WT"/.be/*/*.keeper.idx 2>/dev/null || true
python3 "$_CASE/okay.py" "$JABC" "$WT" >"$WORK/out" 2>"$WORK/err" || {
    echo "--- stderr ---"; cat "$WORK/err"
    echo "--- out ---";    cat "$WORK/out"; _fail "pty click checks failed"; }
grep -q '^DONE' "$WORK/out" || { cat "$WORK/out"; _fail "the pty driver did not finish"; }
sed 's/^/     /' "$WORK/out"

echo "PASS [status/$NAME]"
