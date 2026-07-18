#!/bin/sh
# test/get/conf-state — POST-032: a weave conflict on a pending edit is a
# NORMAL merge outcome (ruling 2026-07-18), not a hard error: the get
# completes, fences stay, ONE durable `con` row lands, exit is 0 and the
# report says "merged with conflicts" in plain words (no GETCONF code).
# A re-get over the unresolved fences adds NO second row and never
# re-weaves fences into fences.  Self-contained on jab (confdrop shape).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/get/conf-state
_WT=$(cd "$_CASE/../../.." && pwd)               # the jsrc root under test
JAB=${JABC:-jab}
command -v "$JAB" >/dev/null 2>&1 || { echo "conf-state: SKIP — no jab" >&2; exit 0; }

: "${TMP:=/tmp}"
WORK="$TMP/$$/conf-state"
rm -rf "$WORK"; mkdir -p "$WORK"
ln -sfn "$_WT" "$WORK/jsrc"                      # exercise THIS get.js
: > "$TMP/$$/.be" 2>/dev/null || true            # be.find firewall

fail() { echo "FAIL [conf-state] $*" >&2; exit 1; }
_srctip() { ( cd "$SRC" && "$JAB" refs 2>/dev/null ) | sed -n 's/^cur: *//p'; }
# _conrows DIR — count durable `con` rows in DIR's wtlog
_conrows() {
    cat > "$WORK/.conrows.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const r=wtlog.open(be.treeAt(process.argv[2]));
let n=0;for(const row of r.rows)if(row.verb==="con")n++;
const u=utf8.Encode(n+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JAB" "$WORK/.conrows.js" "$1" "$_WT" 2>/dev/null
}

# ===== source: c1 base; c2 changes the conflict file AND a clean file =====
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'l1\nl2\nl3\nl4\nl5\n' > conf.txt
printf 'old clean content\n' > clean.txt
"$JAB" post 'c1' >/dev/null 2>&1 || fail "post c1"
C1=$(_srctip)
printf 'l1\nl2\nl3\nl4\nTHEIRS\n' > conf.txt
printf 'NEW clean content\n' > clean.txt
"$JAB" put conf.txt clean.txt >/dev/null 2>&1 || fail "put"
"$JAB" post 'c2' >/dev/null 2>&1 || fail "post c2"
C2=$(_srctip)
[ -n "$C1" ] && [ -n "$C2" ] && [ "$C1" != "$C2" ] || fail "two-commit setup"

# ===== worktree at c1 with an overlapping local edit on conf.txt =====
WT="$WORK/wt"; mkdir -p "$WT"
( cd "$WT" && "$JAB" get "file://$SRC/.be#$C1" ) >/dev/null 2>&1 || fail "clone"
( cd "$WT" && "$JAB" get "?#$C1" ) >/dev/null 2>&1 || fail "pin to c1"
printf 'l1\nl2\nl3\nl4\nMINE\n' > "$WT/conf.txt"

# ===== the conflicted get: a STATE, not an error =====
rc=0
( cd "$WT" && "$JAB" get "?#$C2" ) >"$WORK/get.out" 2>"$WORK/get.err" || rc=$?
[ "$rc" = 0 ] || { cat "$WORK/get.err"; fail "conflict must NOT hard-err (exit=$rc)"; }
grep -q 'GETCONF' "$WORK/get.err" && fail "bare GETCONF code leaked to the user"
grep -q 'merged with conflicts' "$WORK/get.err" || \
    { cat "$WORK/get.err"; fail "missing plain-words conflict state line"; }
grep -q '<<<<' "$WT/conf.txt" || fail "conf.txt lacks conflict markers"
grep -q 'MINE' "$WT/conf.txt" || fail "ours' side missing from the conflict"
grep -q '^NEW clean content$' "$WT/clean.txt" || fail "clean leaf dropped"
[ "$(_conrows "$WT")" = 1 ] || fail "want ONE con row, got $(_conrows "$WT")"

# ===== re-get over the UNRESOLVED fences: no dup row, no nested fences =====
rc=0
( cd "$WT" && "$JAB" get "?#$C2" ) >"$WORK/get2.out" 2>"$WORK/get2.err" || rc=$?
[ "$rc" = 0 ] || { cat "$WORK/get2.err"; fail "re-get over fences hard-erred (exit=$rc)"; }
[ "$(_conrows "$WT")" = 1 ] || fail "re-get stacked a duplicate con row ($(_conrows "$WT"))"
[ "$(grep -c '<<<<' "$WT/conf.txt")" = 1 ] || \
    { cat "$WT/conf.txt"; fail "re-get wove fences into fences"; }

# ===== convergence: hand-resolve, re-get -> clean, resolution kept =====
printf 'l1\nl2\nl3\nl4\nRESOLVED\n' > "$WT/conf.txt"
rc=0
( cd "$WT" && "$JAB" get ) >"$WORK/get3.out" 2>"$WORK/get3.err" || rc=$?
[ "$rc" = 0 ] || { cat "$WORK/get3.err"; fail "resolved re-get exit=$rc"; }
grep -q '^RESOLVED$' "$WT/conf.txt" || fail "re-get clobbered the resolution"

rm -rf "$TMP/$$"
echo "PASS [conf-state]"
