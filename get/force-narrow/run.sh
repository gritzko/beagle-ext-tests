#!/bin/sh
# test/get/force-narrow — GET-047 × GET.mkd 2.4: `get! file.c` is a NARROWED
# FORCEFUL reset — the named dirty path clean-resets to cur's baseline while a
# DIFFERENT dirty file outside the narrow keeps its edits; `get! d/` resets a
# whole subtree the same way.
. "$(dirname "$0")/../../lib/getrepro.sh"

# gr_jbang DIR ARG... — the `get!` verb spelling (the cli sheds the bang into
# --force, GET.mkd "be get!"); same capture contract as gr_jget.
gr_jbang() {
    _d=$1; shift; _rc=0
    ( cd "$_d" && "$JABC" 'get!' "$@" ) >"$WORK/last.out" 2>"$WORK/last.err" || _rc=$?
    printf '%s\n' "$_rc"
}

SRC=$(gr_src src)
gr_jclone "$SRC" "$WORK/jT"

# Dirty TWO files; `get! a.txt` must force-reset ONLY a.txt (b.txt stays dirty).
printf 'DIRTY-A\n' > "$WORK/jT/a.txt"
printf 'DIRTY-B\n' > "$WORK/jT/b.txt"
rc=$(gr_jbang "$WORK/jT" a.txt)
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get! a.txt exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A"          # narrowed: force-reset to baseline
gr_file_is "$WORK/jT/b.txt" "DIRTY-B"    # outside the narrow: untouched

# Narrowed DIR: dirty d/c.txt, `get! d/` resets the subtree; b.txt STILL dirty.
printf 'DIRTY-C\n' > "$WORK/jT/d/c.txt"
rc=$(gr_jbang "$WORK/jT" d/)
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get! d/ exit=$rc"; }
gr_file_is "$WORK/jT/d/c.txt" "C"
gr_file_is "$WORK/jT/b.txt" "DIRTY-B"

pass
