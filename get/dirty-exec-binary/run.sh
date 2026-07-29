#!/bin/sh
# test/get/dirty-exec-binary — GET-056: the D5 dirty-merge gate keys on
# CONTENT, not on checkout's leaf kind.  RULING (gritzko, 2026-07-28):
# symlink, gitlink or BINARY get reset; anything parseable (any text) gets
# MERGED — mergeability is a property of the bytes, not the mode bit.
# (a) a dirty EXECUTABLE text file (kind "x") must 3-way weave, keeping the
#     uncommitted edit AND the exec bit (it used to fall past the
#     `kind === "f"` gate and clean-reset, silently dropping the edit);
# (b) a dirty BINARY 644 file (kind "f") must clean-reset to the target
#     bytes exactly (it used to be fed to weave3 as if it were text).
. "$(dirname "$0")/../../lib/getrepro.sh"

# Base c1: an executable multi-line text file + a NUL-carrying binary blob.
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'l1\nl2\nl3\nl4\nl5\n' > x.sh
chmod 755 x.sh
printf '\0\1\2\3' > bin.dat
"$BE" post 'c1' >/dev/null 2>&1
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"

# Target branch U off c1: x.sh last line l5->U5 (disjoint from ours' edit),
# bin.dat -> entirely new binary bytes.
gr_jclone "$SRC" "$WORK/jU"
cd "$WORK/jU"
printf 'l1\nl2\nl3\nl4\nU5\n' > x.sh
printf '\0\5\6\7' > bin.dat
"$JABC" put x.sh >/dev/null 2>&1 || _fail "put x.sh failed"
"$JABC" put bin.dat >/dev/null 2>&1 || _fail "put bin.dat failed"
"$JABC" post '?U' '#u1' >/dev/null 2>&1 || _fail "post ?U failed"
"$JABC" post '?U' >/dev/null 2>&1 || _fail "publish ?U failed"
CU=$(gr_tip_sha "$WORK/jU")
[ -n "$CU" ] && [ "$CU" != "$C1" ] || _fail "U fork setup"
printf '\0\5\6\7' > "$WORK/binref"          # the target bytes, for cmp

# The local clone, DIRTY on both: x.sh first line l1->X1 (uncommitted,
# disjoint from theirs), bin.dat a different dirty binary edit.
gr_jclone "$SRC" "$WORK/jL"
[ -x "$WORK/jL/x.sh" ] || _fail "clone lost the exec bit on x.sh"
printf 'X1\nl2\nl3\nl4\nl5\n' > "$WORK/jL/x.sh"
printf '\0\1\2\3\4' > "$WORK/jL/bin.dat"

rc=$(gr_jget "$WORK/jL" '?U')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?U exit=$rc"; }

# (a) the dirty EXEC text file weaved: BOTH edits present, mode still exec.
gr_file_is "$WORK/jL/x.sh" "X1
l2
l3
l4
U5"
[ -x "$WORK/jL/x.sh" ] || _fail "x.sh lost the exec bit across the weave"

# (b) the dirty BINARY file clean-reset: EXACTLY the target bytes — no
#     fences, no woven garbage.
cmp -s "$WORK/jL/bin.dat" "$WORK/binref" || { \
    echo "--- bin.dat dump ---"; od -An -c "$WORK/jL/bin.dat"; \
    _fail "bin.dat is not the clean target bytes"; }

pass
