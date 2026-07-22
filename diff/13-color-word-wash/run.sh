#!/bin/sh
# BRO-009 regression: `jab diff:<file> --color` (the bro two-pass side→bg word
# wash, single-sourced through view/bro.js colorDiffHunk).  Exercises every line
# kind the two-pass classifier splits on — MOD_INLINE, MOD_SPLIT, PURE_IN,
# PURE_RM, EQ context — PLUS a multibyte em-dash in a changed line (the regression
# for the double-utf8-encode bug: text bytes emitted RAW, never re-encoded).
# TEST-003: native `be`/`graf` RETIRED (they LAG jab); diff_eq asserts jab's own
# --plain (non-empty, for have) + that --color renders — no native oracle cmp.
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
printf 'keep one\nthe em-dash line\nkeep three\n' > prose.txt
# TEST-003: bare bootstrap post (no pre-put — a leading `jab put` corrupts the
# store bootstrap; `post` auto-stages the fresh files).
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
printf 'keep one\nthe em-dash line EDITED\nkeep three\n' > prose.txt

diff_eq "code: inline + split + add + del" 'diff:code.c'
have '^\+    int x = 42;$'      "code: MOD_INLINE edit"
have '^\+    int z = 99;$'      "code: PURE_IN added line"
have '^-    return 0;$'         "code: PURE_RM deleted line"
diff_eq "prose: multibyte em-dash in a change" 'diff:prose.txt'
have 'EDITED'                   "prose: the em-dash line change"
have 'em-dash' "prose: multibyte em-dash emitted RAW (no double-encode)"
diff_eq "wt-vs-base whole tree (both files)"   'diff:'
have '^\+    int x = 42;$'      "whole tree: code.c change"
have 'EDITED'                   "whole tree: prose.txt change"

pass
