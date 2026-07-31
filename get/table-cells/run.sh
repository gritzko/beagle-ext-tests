#!/bin/sh
# test/get/table-cells — GET-058: one repro per cell of the 13-cell quad
# DECISION table (rows = track vs root, cols = wt vs base), FLAT (D5 leaf).
# FF slice (root == base), so `track vs root` is simply "what theirs changed":
#   in base:  T. W. no-op | T. Wv OURS   | T. Wx stays deleted
#             Tv W. THEIRS | Tv Wv WEAVE3 | Tv Wx THEIRS
#             Tx W. DELETE | Tx Wv OURS keep | Tx Wx no-op
#   not base: To W- THEIRS | To Wo WEAVE3 | T- Wo OURS | T- W- no-op
# BINARY modifies ONLY the both-sides-edited cells (Tv Wv, To Wo) -> OURS +
# conflict.  Every cell is checked, then the run fails with the full red list
# (a per-cell baseline record, not a first-failure abort).
. "$(dirname "$0")/../../lib/getrepro.sh"

RED=""
_green() { echo "ok   $1"; }
_red()   { echo "RED  $1: $2"; RED="$RED $1"; }

# _is CELL PATH CONTENT — the file must exist with exactly CONTENT.
_is() {
    if [ ! -f "$2" ]; then _red "$1" "missing $2"; return 0; fi
    _g=$(cat "$2")
    if [ "$_g" = "$3" ]; then _green "$1"; else _red "$1" "got [$_g] want [$3]"; fi
}
# _gone CELL PATH — the path must not exist.
_gone() {
    if [ -e "$2" ]; then _red "$1" "$2 still exists"; else _green "$1"; fi
}
# _has CELL PATH PATTERN... — every PATTERN must appear in PATH.
_has() {
    _c=$1; _p=$2; shift 2
    if [ ! -f "$_p" ]; then _red "$_c" "missing $_p"; return 0; fi
    for _pat in "$@"; do
        if ! grep -q "$_pat" "$_p"; then _red "$_c" "$_p lacks $_pat"; return 0; fi
    done
    _green "$_c"
}
# _same CELL PATH REF — byte-identical to REF (binary compare).
_same() {
    if cmp -s "$2" "$3"; then _green "$1"; else _red "$1" "$2 differs from $3"; fi
}

_tip() { ( cd "$1" && "$JABC" refs 2>/dev/null ) | sed -n 's/^cur: *//p'; }

# ===========================================================================
# The source: c1 = the BASE tree, c2 = THEIRS (the track advance).  FF, so
# root == base and the track column reads straight off c1 -> c2.
# ===========================================================================
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'B\n'                > t_dot_w_dot.txt   # T. W.
printf 'B\n'                > t_dot_w_v.txt     # T. Wv
printf 'B\n'                > t_dot_w_x.txt     # T. Wx
printf 'B\n'                > t_v_w_dot.txt     # Tv W.
printf 'l1\nl2\nl3\nl4\nl5\n' > t_v_w_v.txt     # Tv Wv (disjoint weave)
printf 'B\n'                > t_v_w_x.txt       # Tv Wx
printf 'B\n'                > t_x_w_dot.txt     # Tx W.
printf 'B\n'                > t_x_w_v.txt       # Tx Wv
printf 'B\n'                > t_x_w_x.txt       # Tx Wx
printf 'BIN\000BASE\n'      > bin_t_v_w_v.dat   # Tv Wv, BINARY
"$BE" post 'c1' >/dev/null 2>&1
C1=$(_tip "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"

printf 'THEIRS\n'             > t_v_w_dot.txt
printf 'l1\nl2\nl3\nl4\nL5\n' > t_v_w_v.txt
printf 'THEIRS\n'             > t_v_w_x.txt
"$BE" delete t_x_w_dot.txt t_x_w_v.txt t_x_w_x.txt >/dev/null 2>&1
printf 'THEIRS\n'             > t_o_w_none.txt  # To W-
printf 'l1\nl2\nl3\nl4\nL5\n' > t_o_w_o.txt     # To Wo (add/add)
printf 'BIN\000THEIRS\n'      > bin_t_v_w_v.dat
printf 'BIN\000THEIRS\n'      > bin_t_o_w_o.dat # To Wo, BINARY
"$BE" put t_v_w_dot.txt t_v_w_v.txt t_v_w_x.txt t_o_w_none.txt t_o_w_o.txt \
    bin_t_v_w_v.dat bin_t_o_w_o.dat >/dev/null 2>&1
"$BE" post 'c2' >/dev/null 2>&1
C2=$(_tip "$SRC")
[ -n "$C2" ] && [ "$C2" != "$C1" ] || _fail "c1/c2 setup"

# ===========================================================================
# ARM 1 — the 10 cells with no add/add overlay (an add/add hits the GETOVRL
# pre-pass, which refuses the WHOLE get, so those two cells get own clones).
# ===========================================================================
A="$WORK/A"; mkdir -p "$A"
( cd "$A" && "$JABC" get "file://$SRC/.be#$C1" ) >/dev/null 2>&1 || _fail "clone A"
printf 'OURS\n'               > "$A/t_dot_w_v.txt"
rm -f "$A/t_dot_w_x.txt"
printf 'X1\nl2\nl3\nl4\nl5\n' > "$A/t_v_w_v.txt"
rm -f "$A/t_v_w_x.txt"
printf 'OURS\n'               > "$A/t_x_w_v.txt"
rm -f "$A/t_x_w_x.txt"
printf 'OURS-UNTRACKED\n'     > "$A/t_none_w_o.txt"     # T- Wo
printf 'BIN\000OURS\n'        > "$A/bin_t_v_w_v.dat"
cp "$A/bin_t_v_w_v.dat" "$WORK/bin_ours.dat"

rc=$(gr_jget "$A" "?#$C2")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "arm1 get ?#$C2 exit=$rc"; }
cp "$WORK/last.out" "$WORK/a.out"; cp "$WORK/last.err" "$WORK/a.err"

_is   "T. W."  "$A/t_dot_w_dot.txt" "B"
_is   "T. Wv"  "$A/t_dot_w_v.txt"   "OURS"
_gone "T. Wx"  "$A/t_dot_w_x.txt"
_is   "Tv W."  "$A/t_v_w_dot.txt"   "THEIRS"
_has  "Tv Wv"  "$A/t_v_w_v.txt"     '^X1$' '^L5$'
_is   "Tv Wx"  "$A/t_v_w_x.txt"     "THEIRS"
_gone "Tx W."  "$A/t_x_w_dot.txt"
_is   "Tx Wv"  "$A/t_x_w_v.txt"     "OURS"
_gone "Tx Wx"  "$A/t_x_w_x.txt"
_is   "To W-"  "$A/t_o_w_none.txt"  "THEIRS"
_is   "T- Wo"  "$A/t_none_w_o.txt"  "OURS-UNTRACKED"
_gone "T- W-"  "$A/t_none_w_none.txt"
# BINARY x (Tv Wv): OURS survives byte-for-byte AND the row is a conflict —
# DIS-080 glyphs (`...!`), a durable `con` row and the plain-words state line.
_same "Tv Wv bin" "$A/bin_t_v_w_v.dat" "$WORK/bin_ours.dat"
if grep -qF '...! bin_t_v_w_v.dat' "$WORK/a.out" \
   && grep -q 'merged with conflicts' "$WORK/a.err" \
   && gr_wtraw "$A" | grep -q 'conbin_t_v_w_v.dat'; then
    _green "Tv Wv bin con"
else
    echo "--- a.out ---"; cat "$WORK/a.out"; echo "--- a.err ---"; cat "$WORK/a.err"
    _red "Tv Wv bin con" "a dirty binary both sides edited must read con"
fi

# ===========================================================================
# ARM 2 — To Wo, TEXT add/add: theirs adds the path, we created our own.  The
# table says WEAVE3; both sides must survive and the get must not hard-err.
# ===========================================================================
B="$WORK/B"; mkdir -p "$B"
( cd "$B" && "$JABC" get "file://$SRC/.be#$C1" ) >/dev/null 2>&1 || _fail "clone B"
printf 'X1\nl2\nl3\nl4\nl5\n' > "$B/t_o_w_o.txt"
rm -f "$B/bin_t_o_w_o.dat" 2>/dev/null || true
rc=$(gr_jget "$B" "?#$C2")
if [ "$rc" != 0 ]; then
    _red "To Wo" "add/add REFUSED the whole get (exit=$rc): $(head -1 "$WORK/last.err")"
else
    _has "To Wo" "$B/t_o_w_o.txt" '^X1$' '^L5$'
fi

# ===========================================================================
# ARM 3 — To Wo, BINARY add/add: OURS + conflict, never woven, never reset.
# ===========================================================================
C="$WORK/C"; mkdir -p "$C"
( cd "$C" && "$JABC" get "file://$SRC/.be#$C1" ) >/dev/null 2>&1 || _fail "clone C"
printf 'BIN\000OURS\n' > "$C/bin_t_o_w_o.dat"
cp "$C/bin_t_o_w_o.dat" "$WORK/bin_ours2.dat"
rc=$(gr_jget "$C" "?#$C2")
if [ "$rc" != 0 ]; then
    _red "To Wo bin" "binary add/add REFUSED the get (exit=$rc): $(head -1 "$WORK/last.err")"
else
    _same "To Wo bin" "$C/bin_t_o_w_o.dat" "$WORK/bin_ours2.dat"
fi

# ===========================================================================
# get! stays the SOLE cleaning path (GET-040 invariant): every cell resets.
# ===========================================================================
F="$WORK/F"; mkdir -p "$F"
( cd "$F" && "$JABC" get "file://$SRC/.be#$C1" ) >/dev/null 2>&1 || _fail "clone F"
printf 'OURS\n'        > "$F/t_x_w_v.txt"
printf 'BIN\000OURS\n' > "$F/bin_t_v_w_v.dat"
printf 'JUNK\n'        > "$F/t_none_w_o.txt"
rc=$(gr_jget "$F" "?#$C2!")
if [ "$rc" != 0 ]; then _red "get! force" "exit=$rc: $(head -1 "$WORK/last.err")"; else
    _gone "get! Tx Wv"  "$F/t_x_w_v.txt"
    _gone "get! untracked" "$F/t_none_w_o.txt"
    if cmp -s "$F/bin_t_v_w_v.dat" "$WORK/bin_ours.dat"; then
        _red "get! bin" "force did not reset a dirty binary"
    else _green "get! bin"; fi
fi

[ -z "$RED" ] || _fail "RED cells:$RED"
pass
