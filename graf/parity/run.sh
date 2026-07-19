#!/bin/sh
#  WORK-011 graf/parity — the work view's registry().counts() ahead/behind is
#  graf-backed and numerically identical to the old keeper closure diff, and a
#  persisted *.graf.idx serves counts() with zero keeper reads.  ABSOLUTE script
#  path so jab treats index.js as a file.
set -eu
_CASE=$(cd "$(dirname "$0")" && pwd)
JABC=${JABC:-${BIN:+$BIN/jab}}; JABC=${JABC:-${BE:-}}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "FAIL [graf/parity] no jab (set BIN=)" >&2; exit 2; }
: "${TMP:=/tmp}"; export TMP
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
"$JABC" "$_CASE/index.js"
