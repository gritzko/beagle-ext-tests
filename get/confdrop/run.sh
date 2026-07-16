#!/bin/sh
# test/get/confdrop — GET-043: a get that hits ONE conflicting file must still
# materialise every OTHER leaf (the old CONFMARK queue-row sentinel threw before
# later dir-reconciles fanned out, silently dropping their leaves while the
# wtlog tip was already advanced — the pulled changes were lost as phantom
# `mod`s).  Self-contained on jab only (no native `be`, no lib/getrepro.sh):
# builds a green-field source with `jab post`, exercises THIS tree's get.js
# via a planted jsrc symlink.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/get/confdrop
_WT=$(cd "$_CASE/../../.." && pwd)               # the jsrc root under test
JAB=${JABC:-jab}
command -v "$JAB" >/dev/null 2>&1 || { echo "confdrop: SKIP — no jab" >&2; exit 0; }

: "${TMP:=/tmp}"
WORK="$TMP/$$/confdrop"
rm -rf "$WORK"; mkdir -p "$WORK"
ln -sfn "$_WT" "$WORK/jsrc"                      # exercise THIS get.js
: > "$TMP/$$/.be" 2>/dev/null || true            # be.find firewall

fail() { echo "FAIL [confdrop] $*" >&2; exit 1; }
# DIS-076: a bare post never mints a ref — the wt's OWN cur (jab refs) is the
# only tip there is; never grep a `.be/refs` ULOG (that file no longer exists).
_srctip() { ( cd "$SRC" && "$JAB" refs 2>/dev/null ) | sed -n 's/^cur: *//p'; }

# ===== source: c1 base; c2 changes BOTH the conflict file and a clean =====
# ===== file in a subdir whose reconcile runs AFTER the conflict leaf  =====
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'l1\nl2\nl3\nl4\nl5\n' > conf.txt
mkdir later; printf 'old clean content\n' > later/clean.txt
"$JAB" post 'c1' >/dev/null 2>&1 || fail "post c1"
C1=$(_srctip)
printf 'l1\nl2\nl3\nl4\nTHEIRS\n' > conf.txt
printf 'NEW clean content\n' > later/clean.txt
"$JAB" put conf.txt later/clean.txt >/dev/null 2>&1 || fail "put"
"$JAB" post 'c2' >/dev/null 2>&1 || fail "post c2"
C2=$(_srctip)
[ -n "$C1" ] && [ -n "$C2" ] && [ "$C1" != "$C2" ] || fail "two-commit setup"

# ===== worktree at c1 with an overlapping local edit on conf.txt =====
WT="$WORK/wt"; mkdir -p "$WT"
( cd "$WT" && "$JAB" get "file://$SRC/.be#$C1" ) >/dev/null 2>&1 || fail "clone"
( cd "$WT" && "$JAB" get "?#$C1" ) >/dev/null 2>&1 || fail "pin to c1"
grep -q '^old clean content$' "$WT/later/clean.txt" || fail "c1 baseline"
printf 'l1\nl2\nl3\nl4\nMINE\n' > "$WT/conf.txt"

# ===== the conflicted get: LOUD on the conflict, NO other leaf dropped =====
rc=0
( cd "$WT" && "$JAB" get "?#$C2" ) >"$WORK/get.out" 2>"$WORK/get.err" || rc=$?
[ "$rc" != 0 ] || fail "a conflict must exit NON-ZERO"
grep -q 'GETCONF' "$WORK/get.err" || { cat "$WORK/get.err"; fail "expected GETCONF"; }
grep -q '<<<<' "$WT/conf.txt" || fail "conf.txt lacks conflict markers"
grep -q 'MINE' "$WT/conf.txt" || fail "ours' side missing from the conflict"
# THE GET-043 assert: the clean remote-changed leaf must be materialised.
grep -q '^NEW clean content$' "$WT/later/clean.txt" || { \
    echo "--- later/clean.txt ---"; cat "$WT/later/clean.txt"; \
    fail "clean leaf DROPPED after the conflict (pulled change lost)"; }

# ===== convergence: hand-resolve, re-get -> exit 0, nothing stale =====
printf 'l1\nl2\nl3\nl4\nRESOLVED\n' > "$WT/conf.txt"
rc=0
( cd "$WT" && "$JAB" get ) >"$WORK/get2.out" 2>"$WORK/get2.err" || rc=$?
[ "$rc" = 0 ] || { cat "$WORK/get2.err"; fail "resolved re-get exit=$rc"; }
grep -q '^NEW clean content$' "$WT/later/clean.txt" || fail "re-get left stale content"
grep -q '^RESOLVED$' "$WT/conf.txt" || fail "re-get clobbered the resolution"

rm -rf "$TMP/$$"
echo "PASS [confdrop]"
