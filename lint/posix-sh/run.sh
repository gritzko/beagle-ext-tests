#!/bin/sh
# Lint: the case scripts must be POSIX sh.  CMakeLists runs every case with
# `sh`, which is dash on Debian/Ubuntu (CI) and busybox ash on Alpine (local).
# ANSI-C quoting is an ash/bash extension that dash passes through LITERALLY,
# so a tab-anchored `grep -a` on a wtlog silently matches nothing there and the
# case fails with a golden mismatch that looks like a jab bug.  The portable
# spelling is a command substitution: grep -a "$(printf '\tpost\t')" FILE.
#
# busybox grep has no --include, so the file set comes from find.  This script
# excludes itself (it must name the offending construct to explain it).

set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)
_TEST=$(cd "$_CASE/../.." && pwd)                   # test/
_SELF=./lint/posix-sh/run.sh

_hits=$(cd "$_TEST" && find . -name '*.sh' ! -path "$_SELF" \
        -exec grep -n -F "\$'\\" /dev/null {} + || true)
if [ -n "$_hits" ]; then
    echo "non-POSIX ANSI-C quoting in test scripts (dash does not expand it):" >&2
    echo "$_hits" >&2
    exit 1
fi
echo "ok   no ANSI-C quoting in test/*.sh"
