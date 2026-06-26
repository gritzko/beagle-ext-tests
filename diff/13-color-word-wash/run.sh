#!/bin/sh
# BRO-009 regression: `jab diff:<file> --color` must byte-match `be --color`
# (the C bro two-pass side→bg word wash), single-sourced through view/bro.js
# (colorDiffHunk).  Exercises every line kind the two-pass classifier splits on
# — MOD_INLINE (small in-place edit), MOD_SPLIT (whole-line rewrite), PURE_IN
# (added line), PURE_RM (deleted line), EQ context — PLUS a multibyte char
# (em-dash) in a changed line, the regression for the double-utf8-encode bug
# (text bytes must be emitted RAW, never re-encoded).  diff_eq asserts both
# --plain (oracle `be`) and --color (oracle `be`, paged via bro) byte-identical.
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

# baseline: a code file (so the tokeniser tags syntax fg under the bg wash) +
# a prose file carrying a multibyte em-dash on a line that will change.
cat > code.c <<'EOF'
#include <stdio.h>
int main(void) {
    int x = 1;
    int y = 2;
    puts("hello");
    return 0;
}
EOF
printf 'keep one\nthe em\xe2\x80\x94dash line\nkeep three\n' > prose.txt
"$BE" put code.c prose.txt >/dev/null 2>&1
"$BE" post -m base >/dev/null 2>&1

# edits: MOD_INLINE (x = 1 -> x = 42), MOD_SPLIT (puts line reworded), PURE_IN
# (an added `int z`), PURE_RM (drop `return 0;`); and reword the em-dash line so
# the multibyte char rides a MOD_SPLIT in/rm pair.
cat > code.c <<'EOF'
#include <stdio.h>
int main(void) {
    int x = 42;
    int y = 2;
    int z = 99;
    puts("hello, world");
}
EOF
printf 'keep one\nthe em\xe2\x80\x94dash line EDITED\nkeep three\n' > prose.txt

diff_eq "code: inline + split + add + del" 'diff:code.c'
diff_eq "prose: multibyte em-dash in a change" 'diff:prose.txt'
diff_eq "wt-vs-base whole tree (both files)"   'diff:'

pass
