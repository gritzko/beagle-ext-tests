#!/bin/sh
#  GIT-016 wire/saveremote — runs the sibling JS unit (ingest.saveRemoteRef round-
#  trip via store.eachRemote).  ABSOLUTE script path so jab treats index.js as a
#  file; its be-relative requires resolve via jab's upward be/-scan.
set -eu
_CASE=$(cd "$(dirname "$0")" && pwd)
JABC=${JABC:-${BIN:+$BIN/jab}}; JABC=${JABC:-${BE:-}}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "FAIL [wire/saveremote] no jab (set BIN=)" >&2; exit 2; }
: "${TMP:=/tmp}"; export TMP
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
"$JABC" "$_CASE/index.js"
