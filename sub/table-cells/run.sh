#!/bin/sh
# test/sub/table-cells — GET-058: the SUB twin of test/get/table-cells.  The
# SAME 13-cell quad decision table must hold for a MOUNTED sub's checkout
# (shared/checkout.js apply) as for the flat D5 leaf — a cell that reads one
# way flat and another way in a sub is exactly the GET-056/GET-057 drift.
# Shape: parent + mounted sub; the sub's pin advances (theirs), the local
# clone's mounted sub carries the wt-column moves, non-force parent get.
. "$(dirname "$0")/../lib/subcase.sh"

RED=""
_green() { echo "ok   $1"; }
_red()   { echo "RED  $1: $2"; RED="$RED $1"; }

_is() {
    if [ ! -f "$2" ]; then _red "$1" "missing $2"; return 0; fi
    _g=$(cat "$2")
    if [ "$_g" = "$3" ]; then _green "$1"; else _red "$1" "got [$_g] want [$3]"; fi
}
_gone() {
    if [ -e "$2" ]; then _red "$1" "$2 still exists"; else _green "$1"; fi
}
_has() {
    _c=$1; _p=$2; shift 2
    if [ ! -f "$_p" ]; then _red "$_c" "missing $_p"; return 0; fi
    for _pat in "$@"; do
        if ! grep -q "$_pat" "$_p"; then _red "$_c" "$_p lacks $_pat"; return 0; fi
    done
    _green "$_c"
}
_same() {
    if cmp -s "$2" "$3"; then _green "$1"; else _red "$1" "$2 differs from $3"; fi
}

sc_build_parent
S="$SUBSTORE"

# ---- the sub's BASE commit (c1): one file per in-base cell -----------------
( cd "$S"
  printf 'B\n'                > t_dot_w_dot.txt
  printf 'B\n'                > t_dot_w_v.txt
  printf 'B\n'                > t_dot_w_x.txt
  printf 'B\n'                > t_v_w_dot.txt
  printf 'l1\nl2\nl3\nl4\nl5\n' > t_v_w_v.txt
  printf 'B\n'                > t_v_w_x.txt
  printf 'B\n'                > t_x_w_dot.txt
  printf 'B\n'                > t_x_w_v.txt
  printf 'B\n'                > t_x_w_x.txt
  printf 'BIN\000BASE\n'      > bin_t_v_w_v.dat
  "$JABC" put t_dot_w_dot.txt t_dot_w_v.txt t_dot_w_x.txt t_v_w_dot.txt \
      t_v_w_v.txt t_v_w_x.txt t_x_w_dot.txt t_x_w_v.txt t_x_w_x.txt \
      bin_t_v_w_v.dat
  "$JABC" post '#sub cells base' ) >"$WORK/s1.out" 2>&1 || \
    { cat "$WORK/s1.out"; _fail "sub base post"; }
SUBTIP1=$(sc_tip "$S"); sc_is40 "$SUBTIP1" "sub tip1"
( cd "$PARSTORE/vendor/sub" && "$JABC" get "file://$S/.be#$SUBTIP1" ) \
    >"$WORK/sadv1.out" 2>&1 || { cat "$WORK/sadv1.out"; _fail "advance mount base"; }
( cd "$PARSTORE" && "$JABC" post '#absorb base' ) >"$WORK/p1.out" 2>&1 \
    || { cat "$WORK/p1.out"; _fail "parent absorb base"; }

# ---- the local clone: its mounted sub sits at the base pin -----------------
T="$WORK/wt"
_rc=$(sc_jget "$T" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { cat "$WORK/last.err"; _fail "clone exit $_rc"; }
W="$T/vendor/sub"
[ -f "$W/t_dot_w_dot.txt" ] || _fail "clone did not materialise the sub cells"

# ---- THEIRS: the sub advances (c2), the parent absorbs the new pin ---------
( cd "$S"
  printf 'THEIRS\n'             > t_v_w_dot.txt
  printf 'l1\nl2\nl3\nl4\nL5\n' > t_v_w_v.txt
  printf 'THEIRS\n'             > t_v_w_x.txt
  printf 'THEIRS\n'             > t_o_w_none.txt
  printf 'l1\nl2\nl3\nl4\nL5\n' > t_o_w_o.txt
  printf 'BIN\000THEIRS\n'      > bin_t_v_w_v.dat
  printf 'BIN\000THEIRS\n'      > bin_t_o_w_o.dat
  "$JABC" delete t_x_w_dot.txt t_x_w_v.txt t_x_w_x.txt >/dev/null 2>&1
  "$JABC" put t_v_w_dot.txt t_v_w_v.txt t_v_w_x.txt t_o_w_none.txt \
      t_o_w_o.txt bin_t_v_w_v.dat bin_t_o_w_o.dat
  "$JABC" post '#sub cells theirs' ) >"$WORK/s2.out" 2>&1 || \
    { cat "$WORK/s2.out"; _fail "sub theirs post"; }
SUBTIP2=$(sc_tip "$S"); sc_is40 "$SUBTIP2" "sub tip2"
[ "$SUBTIP2" != "$SUBTIP1" ] || _fail "sub tip did not advance"
( cd "$PARSTORE/vendor/sub" && "$JABC" get "file://$S/.be#$SUBTIP2" ) \
    >"$WORK/sadv2.out" 2>&1 || { cat "$WORK/sadv2.out"; _fail "advance mount theirs"; }
( cd "$PARSTORE" && "$JABC" post '#absorb theirs' ) >"$WORK/p2.out" 2>&1 \
    || { cat "$WORK/p2.out"; _fail "parent absorb theirs"; }
PARTIP2=$(sc_tip "$PARSTORE"); sc_is40 "$PARTIP2" "par tip2"

# ---- OURS: the wt-column moves inside the MOUNTED sub ----------------------
printf 'OURS\n'               > "$W/t_dot_w_v.txt"
rm -f "$W/t_dot_w_x.txt"
printf 'X1\nl2\nl3\nl4\nl5\n' > "$W/t_v_w_v.txt"
rm -f "$W/t_v_w_x.txt"
printf 'OURS\n'               > "$W/t_x_w_v.txt"
rm -f "$W/t_x_w_x.txt"
printf 'OURS-UNTRACKED\n'     > "$W/t_none_w_o.txt"
printf 'X1\nl2\nl3\nl4\nl5\n' > "$W/t_o_w_o.txt"
printf 'BIN\000OURS\n'        > "$W/bin_t_v_w_v.dat"
printf 'BIN\000OURS\n'        > "$W/bin_t_o_w_o.dat"
cp "$W/bin_t_v_w_v.dat" "$WORK/bin_ours.dat"

_rc=0
( cd "$T" && "$JABC" get "file://$PARSTORE/.be#$PARTIP2" ) \
    >"$WORK/g.out" 2>"$WORK/g.err" || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/g.err"; _fail "sub update get exit $_rc"; }

_is   "sub T. W."  "$W/t_dot_w_dot.txt" "B"
_is   "sub T. Wv"  "$W/t_dot_w_v.txt"   "OURS"
_gone "sub T. Wx"  "$W/t_dot_w_x.txt"
_is   "sub Tv W."  "$W/t_v_w_dot.txt"   "THEIRS"
_has  "sub Tv Wv"  "$W/t_v_w_v.txt"     '^X1$' '^L5$'
_is   "sub Tv Wx"  "$W/t_v_w_x.txt"     "THEIRS"
_gone "sub Tx W."  "$W/t_x_w_dot.txt"
_is   "sub Tx Wv"  "$W/t_x_w_v.txt"     "OURS"
_gone "sub Tx Wx"  "$W/t_x_w_x.txt"
_is   "sub To W-"  "$W/t_o_w_none.txt"  "THEIRS"
_has  "sub To Wo"  "$W/t_o_w_o.txt"     '^X1$' '^L5$'
_is   "sub T- Wo"  "$W/t_none_w_o.txt"  "OURS-UNTRACKED"
_gone "sub T- W-"  "$W/t_none_w_none.txt"
# BINARY modifies the two both-sides-edited cells only: OURS + conflict.
_same "sub Tv Wv bin" "$W/bin_t_v_w_v.dat" "$WORK/bin_ours.dat"
if od -An -c "$W/.be" | tr -d ' \n' | grep -q 'con'; then
    _green "sub bin con"
else
    _red "sub bin con" "no durable con row for the dirty-binary both-sides cells"
fi

[ -z "$RED" ] || _fail "RED cells:$RED"
pass
