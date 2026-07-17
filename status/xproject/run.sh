#!/bin/sh
# test/status/xproject — STATUS-010: `jab status ///X` on a main-tree sub that is
# anchored to a DIFFERENT project must compute divergence against the TARGET's own
# project trunk ([/wiki/URI] steps 4-5.3: the shard derives from the arg's RESOLVED
# path — the sub's own `.be` anchor — never re-anchored to the caller/parent).
# Fixture: one shared store, three shards.  The parent project (`par`) owns the
# main tree; `ext/` is a mounted sub of project `ext` (based one commit BEHIND its
# trunk); `orph/` is a sub of project `orph` whose shard has NO trunk ref.  RED
# before the fix: the bare-`?` track resolved in the PARENT's shard — par's trunk
# tip walked as a `miss` row + the sub's whole log as `post` ("behind 1, ahead N").
# GREEN after: ext reads `(behind 1)` vs ITS trunk; an unresolvable track (orph)
# yields NO divergence rows — never a silently-wrong foreign DAG.  Registered by
# the be/test glob as be-js-status-xproject — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/status/xproject
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "status/xproject: cannot locate jab (set BIN=)" >&2; exit 2; }
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "status/xproject: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=xproject
WORK="$TMP/$$/status/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink (jab resolves the
# extension via its upward jsrc-scan from the worktree cwd).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [status/$NAME] $*" >&2; exit 1; }
_is40() {
    case "$1" in
        ????????????????????????????????????????) ;;
        *) _fail "$2: not 40-hex: '$1'" ;;
    esac
}
_tip() { awk -F'\t' '$2=="post"{sub("\\?#","",$3); t=$3} END{print t}' "$1"; }

# --- FIXTURE: two source primaries mint the two projects' commits ------------
# ext: two commits — the sub will be BASED at c0 while trunk is c1 (behind 1).
mkdir -p "$WORK/srcext/.be"
( cd "$WORK/srcext"
  printf 'ext v1\n' > lib.c
  "$JABC" post '#ext c0' && printf 'ext v2\n' > lib.c \
      && "$JABC" put lib.c && "$JABC" post '#ext c1' ) >/dev/null 2>&1 \
    || _fail "ext primary setup"
EXTC0=$(awk -F'\t' '$2=="post"{sub("\\?#","",$3); print $3; exit}' "$WORK/srcext/.be/wtlog")
EXTC1=$(_tip "$WORK/srcext/.be/wtlog")
_is40 "$EXTC0" "ext c0"; _is40 "$EXTC1" "ext c1"
[ "$EXTC0" != "$EXTC1" ] || _fail "fixture: ext trunk did not move"
# par: ONE commit carrying plain `ext/`+`orph/` subdirs — a resolver that lands
# in par's shard can descend those paths, so a context slip walks par's DAG.
mkdir -p "$WORK/srcpar/.be" "$WORK/srcpar/ext" "$WORK/srcpar/orph"
( cd "$WORK/srcpar"
  printf 'int main(){}\n' > main.c
  printf 'par stub\n' > ext/dummy.c
  printf 'par stub\n' > orph/dummy.c
  "$JABC" post '#par c0' ) >/dev/null 2>&1 || _fail "par primary setup"
PARTIP=$(_tip "$WORK/srcpar/.be/wtlog"); _is40 "$PARTIP" "par tip"
PAR8=$(printf '%s' "$PARTIP" | cut -c1-8)
EXT8=$(printf '%s' "$EXTC1" | cut -c1-8)

# --- one shared store, three shards; orph gets NO trunk ref ------------------
STORE="$WORK/store"
mkdir -p "$STORE/.be/par" "$STORE/.be/ext" "$STORE/.be/orph"
cp "$WORK/srcpar/.be/"*.keeper* "$STORE/.be/par/"
cp "$WORK/srcext/.be/"*.keeper* "$STORE/.be/ext/"
cp "$WORK/srcext/.be/"*.keeper* "$STORE/.be/orph/"
S1=$(awk -F'\t' 'NR==1{print $1}' "$WORK/srcpar/.be/wtlog")
S2=$(awk -F'\t' 'NR==1{print $1}' "$WORK/srcext/.be/wtlog")
printf '%s\tpost\t?#%s\n' "$S1" "$PARTIP" > "$STORE/.be/par/refs"
printf '%s\tpost\t?#%s\n' "$S2" "$EXTC1"  > "$STORE/.be/ext/refs"

# --- the parent project tree: main tree on par, two foreign-project subs -----
PROJ="$WORK/proj"
mkdir -p "$PROJ/ext" "$PROJ/orph" "$PROJ/work/WT"
printf 'int main(){}\n' > "$PROJ/main.c"
printf '%s\trepo\tfile:%s/.be/par/\n%s\tget\t?#%s\n' "$S1" "$STORE" "$S2" "$PARTIP" > "$PROJ/.be"
printf 'ext v1\n' > "$PROJ/ext/lib.c"
printf '%s\tget\tfile:%s/.be/?/ext\n%s\tget\t?#%s\n' "$S1" "$STORE" "$S2" "$EXTC0" > "$PROJ/ext/.be"
printf 'ext v1\n' > "$PROJ/orph/lib.c"
printf '%s\tget\tfile:%s/.be/?/orph\n%s\tget\t?#%s\n' "$S1" "$STORE" "$S2" "$EXTC0" > "$PROJ/orph/.be"
printf 'int main(){}\n' > "$PROJ/work/WT/main.c"
printf '%s\tget\tfile:%s/.be/?/par\n%s\tget\t?#%s\n' "$S1" "$STORE" "$S2" "$PARTIP" > "$PROJ/work/WT/.be"

# --- 1. `status ///ext` from a worktree: divergence vs EXT's OWN trunk -------
( cd "$PROJ/work/WT" && "$JABC" status ///ext ) > "$WORK/st1.out" 2>"$WORK/st1.err" \
    || { cat "$WORK/st1.err"; _fail "status ///ext failed"; }
grep -qF "(behind 1)" "$WORK/st1.out" || {
    echo "--- status ///ext ---"; cat "$WORK/st1.out"
    _fail "no (behind 1) vs the target's own trunk"
}
grep -q "ahead" "$WORK/st1.out" && {
    echo "--- status ///ext ---"; cat "$WORK/st1.out"
    _fail "phantom ahead rows — cur's log walked against a foreign tip"
}
# BRO-030: quad default — an unabsorbed track (behind) commit reads `o...`.
grep -qE "o\.\.\.[[:space:]]+\?$EXT8" "$WORK/st1.out" || {
    echo "--- status ///ext ---"; cat "$WORK/st1.out"
    _fail "no o... behind-commit row for ext's own trunk tip ?$EXT8"
}
grep -qF "$PAR8" "$WORK/st1.out" && {
    echo "--- status ///ext ---"; cat "$WORK/st1.out"
    _fail "FOREIGN project tip $PAR8 leaked into the rows"
}

# --- 2. unresolvable track (no trunk ref in orph's shard): NO divergence -----
( cd "$PROJ/work/WT" && "$JABC" status ///orph ) > "$WORK/st2.out" 2>"$WORK/st2.err" \
    || { cat "$WORK/st2.err"; _fail "status ///orph failed"; }
grep -qE "\((behind|ahead)" "$WORK/st2.out" && {
    echo "--- status ///orph ---"; cat "$WORK/st2.out"
    _fail "unresolvable track still reports divergence"
}
# BRO-030: quad default — a commit row is `<quad4> ?<hashlet>`; orph must emit none.
grep -qE "[.oxvOV!]{4}[[:space:]]+\?[0-9a-f]" "$WORK/st2.out" && {
    echo "--- status ///orph ---"; cat "$WORK/st2.out"
    _fail "unresolvable track emits commit rows (silent wrong DAG walk)"
}
grep -qF "$PAR8" "$WORK/st2.out" && {
    echo "--- status ///orph ---"; cat "$WORK/st2.out"
    _fail "FOREIGN project tip $PAR8 leaked into orph's status"
}
# BRO-030: orph is clean → no dirty rows; assert the summary frame proves status
# classified its OWN shard (rather than erroring / walking a foreign DAG).
grep -q "^?" "$WORK/st2.out" || {
    echo "--- status ///orph ---"; cat "$WORK/st2.out"
    _fail "orph status emitted no summary (did not classify its own shard)"
}

echo "PASS [status/$NAME]"
