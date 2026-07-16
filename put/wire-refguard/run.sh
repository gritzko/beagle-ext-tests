#!/bin/sh
#  GIT-016 put/wire-refguard — runs the sibling JS unit (resolveRef branch->refs/
#  guards; plain-text refusal shape).  jab resolves index.js's be-relative requires
#  via its own upward be/-scan; pass the ABSOLUTE script path (a file, not a
#  bareword) so `jab` does not treat `index.js` as a be/-module.
set -eu
_CASE=$(cd "$(dirname "$0")" && pwd)
JABC=${JABC:-${BIN:+$BIN/jab}}; JABC=${JABC:-${BE:-}}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "FAIL [put/wire-refguard] no jab (set BIN=)" >&2; exit 2; }
: "${TMP:=/tmp}"; export TMP
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
"$JABC" "$_CASE/index.js"
