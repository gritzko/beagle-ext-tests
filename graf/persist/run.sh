#!/bin/sh
#  GRAF-003 graf/persist — runs the sibling JS unit (the work registry lands
#  its graf memtable at the end of a render run, so the NEXT run answers every
#  ahead/behind pair off the `*.graf.idx` runs with zero walks).  ABSOLUTE
#  script path so jab treats index.js as a file.
set -eu
_CASE=$(cd "$(dirname "$0")" && pwd)
JABC=${JABC:-${BIN:+$BIN/jab}}; JABC=${JABC:-${BE:-}}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "FAIL [graf/persist] no jab (set BIN=)" >&2; exit 2; }
: "${TMP:=/tmp}"; export TMP
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
"$JABC" "$_CASE/index.js"
