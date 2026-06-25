#!/bin/sh
# JAB-014 parity: file-scoped RANGE diff (`diff:foo.c?v1#v2`, the legacy
# `?from#to` form) and the canonical `?from..to` form, across three tagged
# revisions.  Mirrors beagle/test/diff/01-3revs.  Loop `jab loop.js diff <uri>`
# vs the native dog producer (be --plain / graf --color), byte-identical.
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

mk() { printf '#include <stdio.h>\n\nint main(void) {\n%s    return 0;\n}\n' "$1" > foo.c; }

mk '    puts("hello");\n'
"$BE" put foo.c >/dev/null 2>&1
"$BE" post -m v1 '?v1' >/dev/null 2>&1

mk '    puts("hello, world");\n'
"$BE" put foo.c >/dev/null 2>&1
"$BE" post -m v2 '?v2' >/dev/null 2>&1

mk '    puts("hello, world!");\n    fflush(stdout);\n'
"$BE" put foo.c >/dev/null 2>&1
"$BE" post -m v3 '?v3' >/dev/null 2>&1

diff_eq "file v1#v2 (legacy range)"   'diff:foo.c?v1#v2'
diff_eq "file v2#v3 (legacy range)"   'diff:foo.c?v2#v3'
diff_eq "file v1..v2 (canonical)"     'diff:foo.c?v1..v2'
diff_eq "file v1..v3 (canonical)"     'diff:foo.c?v1..v3'

pass
