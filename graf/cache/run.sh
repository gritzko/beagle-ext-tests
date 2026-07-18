#!/bin/sh
#  GRAF-001 graf/cache — runs the sibling JS unit (shared/graf.js ahead/behind
#  pair cache: index-first lookup, recurrence, merge paint, saturation,
#  truncation no-cache guard, run persistence).  ABSOLUTE script path so jab
#  treats index.js as a file.
set -eu
_CASE=$(cd "$(dirname "$0")" && pwd)
JABC=${JABC:-${BIN:+$BIN/jab}}; JABC=${JABC:-${BE:-}}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "FAIL [graf/cache] no jab (set BIN=)" >&2; exit 2; }
: "${TMP:=/tmp}"; export TMP
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
"$JABC" "$_CASE/index.js"
