#!/bin/sh
# test/sub/dirty-exec-keep — GET-056b: the SUB checkout merges by CONTENT,
# not by the mode bit.  RULING (gritzko): on a non-force get — text clean:
# theirs; text dirty: WEAVE merge; binary clean: theirs; binary dirty: ours.
# checkout.js:203 used to gate the dirty-keep on `kind === "f"`, so a dirty
# EXECUTABLE text file in a mounted sub was clean-reset — the edit silently
# dropped (the GET-057 incident).  Shape: parent + mounted sub; a tracked 755
# TEXT file in the sub is dirtied on line 1; the sub advances upstream editing
# the SAME file's last line (disjoint) + an unrelated file; non-force parent
# update get → the weave must land BOTH edits, exec bit intact.
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent

# sub upstream: an executable multi-line TEXT file.
( cd "$SUBSTORE" && printf 'l1\nl2\nl3\nl4\nl5\n' > x.sh && chmod 755 x.sh \
  && "$JABC" put x.sh && "$JABC" post '#sub xsh' ) >"$WORK/s1.out" 2>&1 \
    || { cat "$WORK/s1.out"; _fail "sub x.sh post"; }
SUBTIP1=$(sc_tip "$SUBSTORE"); sc_is40 "$SUBTIP1" "sub tip1"

# the parent's own mounted sub follows; the parent absorb post bumps the pin.
( cd "$PARSTORE/vendor/sub" && "$JABC" get "file://$SUBSTORE/.be#$SUBTIP1" ) \
    >"$WORK/sadv1.out" 2>&1 || { cat "$WORK/sadv1.out"; _fail "advance mount"; }
( cd "$PARSTORE" && "$JABC" post '#absorb x.sh' ) >"$WORK/p1.out" 2>&1 \
    || { cat "$WORK/p1.out"; _fail "parent absorb x.sh"; }

# the local clone; x.sh must arrive executable.
T1="$WORK/wt"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { cat "$WORK/last.err"; _fail "clone exit $_rc"; }
[ -x "$T1/vendor/sub/x.sh" ] || _fail "clone lost the exec bit on x.sh"

# DIRTY the exec text file in the mounted sub (uncommitted local edit).
printf 'X1\nl2\nl3\nl4\nl5\n' > "$T1/vendor/sub/x.sh"

# the sub advances upstream: x.sh's LAST line (disjoint from ours' edit) and
# an unrelated file; the parent absorbs.
( cd "$SUBSTORE" && printf 'l1\nl2\nl3\nl4\nU5\n' > x.sh \
  && printf 'sub payload v2\n' > lib.c \
  && "$JABC" post '#sub v2' ) >"$WORK/s2.out" 2>&1 \
    || { cat "$WORK/s2.out"; _fail "sub v2 post"; }
SUBTIP2=$(sc_tip "$SUBSTORE"); sc_is40 "$SUBTIP2" "sub tip2"
[ "$SUBTIP2" != "$SUBTIP1" ] || _fail "sub tip did not advance"
( cd "$PARSTORE/vendor/sub" && "$JABC" get "file://$SUBSTORE/.be#$SUBTIP2" ) \
    >"$WORK/sadv2.out" 2>&1 || { cat "$WORK/sadv2.out"; _fail "advance mount v2"; }
( cd "$PARSTORE" && "$JABC" post '#absorb v2' ) >"$WORK/p2.out" 2>&1 \
    || { cat "$WORK/p2.out"; _fail "parent absorb v2"; }
PARTIP2=$(sc_tip "$PARSTORE"); sc_is40 "$PARTIP2" "par tip2"

# non-force update get in the clone: the sub follows the pin.
_rc=0
( cd "$T1" && "$JABC" get "file://$PARSTORE/.be#$PARTIP2" ) \
    >"$WORK/g.out" 2>"$WORK/g.err" || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/g.err"; _fail "update get exit $_rc"; }

# the unrelated file fast-forwards to theirs...
[ "$(cat "$T1/vendor/sub/lib.c")" = "sub payload v2" ] \
    || _fail "sub lib.c did not follow the pin advance"

# ...and the dirty exec TEXT file WEAVED: BOTH edits present, exec bit intact.
[ "$(cat "$T1/vendor/sub/x.sh")" = "X1
l2
l3
l4
U5" ] || _fail "dirty exec x.sh did not weave: [$(cat "$T1/vendor/sub/x.sh")]"
[ -x "$T1/vendor/sub/x.sh" ] || _fail "x.sh lost the exec bit"

pass
