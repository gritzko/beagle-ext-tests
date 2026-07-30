#!/bin/sh
# test/sub/dirty-binary-keep — GET-056b: the SUB checkout merges by CONTENT,
# not by the mode bit.  RULING (gritzko): on a non-force get — text clean:
# theirs; text dirty: weave merge; binary clean: theirs; binary dirty: OURS.
# A dirty BINARY file (NUL in the first bytes) is not weavable, and an
# uncommitted edit is never silently dropped — ours stays.  Shape: parent +
# mounted sub; a tracked 644 BINARY file in the sub is dirtied; the sub
# advances upstream editing the SAME binary + an unrelated file; non-force
# parent update get → bin.dat keeps OUR dirty bytes, lib.c follows theirs.
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent

# sub upstream: a tracked BINARY 644 file (NUL in the first bytes).
( cd "$SUBSTORE" && printf '\0\1\2\3' > bin.dat \
  && "$JABC" put bin.dat && "$JABC" post '#sub bindat' ) >"$WORK/s1.out" 2>&1 \
    || { cat "$WORK/s1.out"; _fail "sub bin.dat post"; }
SUBTIP1=$(sc_tip "$SUBSTORE"); sc_is40 "$SUBTIP1" "sub tip1"
printf '\0\1\2\3' > "$WORK/binref"          # the base bytes, for cmp

# the parent's own mounted sub follows; the parent absorb post bumps the pin.
( cd "$PARSTORE/vendor/sub" && "$JABC" get "file://$SUBSTORE/.be#$SUBTIP1" ) \
    >"$WORK/sadv1.out" 2>&1 || { cat "$WORK/sadv1.out"; _fail "advance mount"; }
( cd "$PARSTORE" && "$JABC" post '#absorb bin.dat' ) >"$WORK/p1.out" 2>&1 \
    || { cat "$WORK/p1.out"; _fail "parent absorb bin.dat"; }

# the local clone.
T1="$WORK/wt"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { cat "$WORK/last.err"; _fail "clone exit $_rc"; }
cmp -s "$T1/vendor/sub/bin.dat" "$WORK/binref" || _fail "clone bin.dat wrong"

# DIRTY the binary in the mounted sub (uncommitted local edit).
printf '\0\1\2\3\4' > "$T1/vendor/sub/bin.dat"
printf '\0\1\2\3\4' > "$WORK/oursref"       # our dirty bytes, for cmp

# the sub advances upstream: the SAME binary changes AND an unrelated file.
( cd "$SUBSTORE" && printf '\0\5\6\7' > bin.dat \
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

# ...and the dirty BINARY keeps OUR bytes — never dropped, never woven.
cmp -s "$T1/vendor/sub/bin.dat" "$WORK/oursref" || { \
    echo "--- bin.dat dump ---"; od -An -c "$T1/vendor/sub/bin.dat"; \
    _fail "dirty binary bin.dat lost OUR bytes"; }

pass
