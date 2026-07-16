#!/bin/sh
# TEST-003 jab-intrinsic: file-scoped RANGE diff (`diff:foo.c?v1#v2`, the legacy
# `?from#to` form) and the canonical `?from..to` form across three tagged revs.
# Native `be`/`graf` are RETIRED (they LAG jab); diff_eq now asserts jab's own
# `--plain` (non-empty, in $WORK/j.plain for have/miss) + `--color` render.
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

mk() { printf '#include <stdio.h>\n\nint main(void) {\n%s    return 0;\n}\n' "$1" > foo.c; }

# TEST-003: the FIRST post has NO preceding `put` (a leading pre-post `jab put`
# corrupts the store bootstrap; `post ?v1` auto-stages the fresh file).
mk '    puts("hello");\n'
"$BE" post -m v1 '?v1' >/dev/null 2>&1
# DIS-076: a message-post never mints/moves a ref — publish the tag explicitly
# (the `post "?<branch>"` pattern) so `?v1` is later resolvable.
"$BE" post '?v1' >/dev/null 2>&1

mk '    puts("hello, world");\n'
"$BE" put foo.c >/dev/null 2>&1
"$BE" post -m v2 '?v2' >/dev/null 2>&1
"$BE" post '?v2' >/dev/null 2>&1

mk '    puts("hello, world!");\n    fflush(stdout);\n'
"$BE" put foo.c >/dev/null 2>&1
"$BE" post -m v3 '?v3' >/dev/null 2>&1
"$BE" post '?v3' >/dev/null 2>&1

diff_eq "file v1#v2 (legacy range)"   'diff:foo.c?v1#v2'
have '^\+    puts\("hello, world"\);' "v1#v2: v2 line added"
have '^-    puts\("hello"\);'         "v1#v2: v1 line removed"
diff_eq "file v2#v3 (legacy range)"   'diff:foo.c?v2#v3'
have 'fflush\(stdout\);'              "v2#v3: v3 adds fflush"
diff_eq "file v1..v2 (canonical)"     'diff:foo.c?v1..v2'
have '^\+    puts\("hello, world"\);' "v1..v2: canonical form matches legacy"
diff_eq "file v1..v3 (canonical)"     'diff:foo.c?v1..v3'
have 'fflush\(stdout\);'              "v1..v3: spans to v3"

pass
