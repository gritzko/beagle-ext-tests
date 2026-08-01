#!/bin/sh
# test/get/line-diverged — GET-053 × /wiki/GET "Forceful execution" (gritzko
# 2026-08-01): "The regular form can only do fast-forward or fast-backward,
# refuses otherwise."  A DIVERGED target is refused in PLAIN WORDS before any
# wtlog append or wt motion; `get!` is the door that adopts it (any commit,
# local changes discarded).
# RED at GET-053 filing: the GET-048 machinery plain-RESETS a diverged target
# (rc=0, the wt walks onto the other line, a get row lands) — the GET-014
# silent-clobber class.
. "$(dirname "$0")/../../lib/getrepro.sh"

# Common base c1 in a shared local store (a local jclone REDIRECTS to the
# source store, so both worktrees' published branches meet in SRC/.be).
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt; printf 'B\n' > b.txt
"$BE" post 'c1' >/dev/null 2>&1
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"

# Local branch L: a.txt A->A2, published (DIS-076: explicit ref post).
gr_jclone "$SRC" "$WORK/jL"
cd "$WORK/jL"
printf 'A2\n' > a.txt
"$JABC" put a.txt >/dev/null 2>&1 || _fail "put a.txt failed"
"$JABC" post '?L' '#l1' >/dev/null 2>&1 || _fail "post ?L failed"
"$JABC" post '?L' >/dev/null 2>&1 || _fail "publish ?L failed"

# Target branch U: b.txt B->B2 off the SAME c1 — a genuine DAG fork.
gr_jclone "$SRC" "$WORK/jU"
cd "$WORK/jU"
printf 'B2\n' > b.txt
"$JABC" put b.txt >/dev/null 2>&1 || _fail "put b.txt failed"
"$JABC" post '?U' '#u1' >/dev/null 2>&1 || _fail "post ?U failed"
"$JABC" post '?U' >/dev/null 2>&1 || _fail "publish ?U failed"
CU=$(gr_tip_sha "$WORK/jU")
[ -n "$CU" ] || _fail "L/U fork setup"

PRE=$(gr_wtraw "$WORK/jL")

# 1. the REFUSAL: a bare-form switch onto the other line is not allowed.
rc=$(gr_jget "$WORK/jL" '?U')
[ "$rc" != 0 ] || { cat "$WORK/last.out"; _fail "diverged get ?U was ACCEPTED"; }

# 2. plain words, never a bare code: the line, and BOTH doors out of it.
grep -q 'not on this line' "$WORK/last.err" \
    || { cat "$WORK/last.err"; _fail "refusal does not say 'not on this line'"; }
grep -q 'patch' "$WORK/last.err" \
    || { cat "$WORK/last.err"; _fail "refusal does not point at \`patch\`"; }
grep -q 'get!' "$WORK/last.err" \
    || { cat "$WORK/last.err"; _fail "refusal does not point at \`get!\`"; }

# 3. nothing moved: the wt still carries ours, and the wtlog gained NO row
#    (the gate fires BEFORE the append — GET-016/GET-018 atomicity line).
gr_file_is "$WORK/jL/a.txt" "A2"
gr_file_is "$WORK/jL/b.txt" "B"
[ "$(gr_wtraw "$WORK/jL")" = "$PRE" ] \
    || { echo "--- wtlog grew ---"; gr_wtraw "$WORK/jL"; echo; \
         _fail "refused get still appended a wtlog row"; }

# 4. the bang REACHES it: `get!` adopts the diverged target wholesale.
_rc=0
( cd "$WORK/jL" && "$JABC" get! '?U' ) >"$WORK/f.out" 2>"$WORK/f.err" || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/f.err"; _fail "get! ?U exit=$_rc"; }
gr_file_is "$WORK/jL/a.txt" "A"
gr_file_is "$WORK/jL/b.txt" "B2"
gr_wtlog_has "$WORK/jL" "get\?U#$CU"

pass
