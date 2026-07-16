#!/bin/sh
# test/serve/uploadpack — GIT-020: the JS keeper SERVE side.  A host-less `be:`
# LOCAL-exec fetch runs jab-to-jab (KEEPER_BIN=jab → `jab upload-pack`), fully
# native-free: the source is seeded with `jab post` (NOT native `be`), cloned
# over the be:// wire, and the checked-out worktree is asserted equal.  Case 2
# drives `jab upload-pack` directly with a want AND the tip as a `have`, proving
# have-based negotiation trims the pack to zero new objects.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)            # test/serve/uploadpack
_ROOT=$(cd "$_CASE/../.." && pwd)               # repo root (test/)
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
_BIN=${BIN:-$(dirname "${BE:-/nonexistent}")}
JAB=${JABC:-$_BIN/jab}
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "SKIP [uploadpack] no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JAB" ] || { echo "SKIP [uploadpack] no jab at $JAB" >&2; exit 0; }

# GIT-020: the WHOLE point — the wire runs jab-to-jab.  KEEPER_BIN=jab so the
# `be:` local-exec spawns `jab upload-pack`, no native keeper anywhere.
export KEEPER_BIN="$JAB"
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"
WORK="$TMP/$$/js-serve-uploadpack"
rm -rf "$WORK"; mkdir -p "$WORK"
# Plant the `be -> <be/>` shard symlink above the scratch so bareword `jab`
# resolves the extension via its upward be/-scan.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [uploadpack] $*" >&2; exit 1; }

# --- seed a source store with jab post (native-free) -----------------------
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt; printf 'B\n' > b.txt
mkdir d; printf 'C\n' > d/c.txt
"$JAB" post 'c1' >/dev/null 2>&1 || _fail "jab post c1 failed"
# POST-027: DIS-076 — a commit mints no ref; publish trunk for the serve.
"$JAB" post '?' >/dev/null 2>&1 || _fail "jab post ? failed"

REMOTE="be:$SRC/.be?/src"
REMOTE_SEL="$SRC/.be?/src"          # the serve-path arg `jab upload-pack` sees

# --- case 1: fresh clone over the be:// wire (jab upload-pack serves) -------
DST="$WORK/clone1"; mkdir -p "$DST"
( cd "$DST" && "$JAB" get "$REMOTE" ) >"$WORK/get1.out" 2>"$WORK/get1.err" \
    || { cat "$WORK/get1.err" >&2; _fail "get1 (fresh clone) failed"; }
for f in a.txt b.txt d/c.txt; do
    [ -f "$DST/$f" ] || _fail "clone missing $f"
    [ "$(cat "$DST/$f")" = "$(cat "$SRC/$f")" ] || _fail "clone $f content mismatch"
done
echo "  case1 ok: fresh clone round-trips ($REMOTE)"

# --- case 2: want/have negotiation trims the pack (direct upload-pack) ------
# The trunk tip (last `#<40hex>` refs row).  Build want+flush+have+done pkt-lines
# and drive `jab upload-pack` on stdin; the served pack must carry ZERO objects
# (the client already has everything reachable from the want).
TIP=$(od -An -c "$SRC/.be/refs" 2>/dev/null | tr -d ' \n' \
      | grep -oE '#[0-9a-f]{40}' | tail -1 | tr -d '#')
[ -n "$TIP" ] || _fail "could not read source trunk tip"
_pktline() { printf '%04x%s\n' $(( ${#1} + 5 )) "$1"; }   # +4 hdr +1 newline
{ _pktline "want $TIP ofs-delta"; printf '0000';
  _pktline "have $TIP"; _pktline "done"; } > "$WORK/req.bin"
"$JAB" upload-pack "$REMOTE_SEL" < "$WORK/req.bin" > "$WORK/resp.bin" 2>/dev/null \
    || _fail "jab upload-pack (want/have) failed"
# A 0-object pack is the fixed 12-byte header `PACK \0\0\0\002 \0\0\0\0` (version
# 2, object-count 0).  od the byte stream, flatten, and require that sequence —
# portable (BusyBox od/tr/grep), no byte-offset -b.  The full-pack case (case 1)
# streamed 6 objects, so this ZERO-count is the have-negotiation proof.
RESP=$(od -An -tx1 "$WORK/resp.bin" | tr -d ' \n')
case "$RESP" in
    *5041434b0000000200000000*) : ;;                       # PACK v2 nobj=0
    *) _fail "have-based pack is not empty (expected PACK v2 nobj=0)" ;;
esac
echo "  case2 ok: want/have negotiation trims pack to 0 objects"

echo "PASS [uploadpack]"
