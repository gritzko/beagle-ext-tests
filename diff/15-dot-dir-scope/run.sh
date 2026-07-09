#!/bin/sh
# BE-037 test/diff/15-dot-dir-scope — a `./`-prefixed arg must scope the wt
# diff exactly like the bare form: parseDiffArg canonicalizes the path slot,
# so the classifier prefix compare sees `sub/…`, never the match-nothing
# `./sub/…`, and a `./file` no longer reads as wholly-added.  RED-first.
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

mkdir -p sub other
printf 'alpha\nbeta\n' > sub/in.c
printf 'omega\n' > other/out.c
"$BE" post -m base >/dev/null 2>&1

# dirty BOTH dirs: a dir scope must show sub/ only, never other/.
printf 'alpha\nBETA mod\n' > sub/in.c
printf 'OMEGA mod\n' > other/out.c

diff_jab "bare dir scope" 'sub'
have 'BETA mod'  "bare scope: sub/ edit present"
miss 'OMEGA'     "bare scope: other/ edit absent"
cp "$WORK/j.plain" "$WORK/bare.plain"

diff_jab "./ dir scope" './sub'
have 'BETA mod'  "./ scope: sub/ edit present"
miss 'OMEGA'     "./ scope: other/ edit absent"
cmp -s "$WORK/bare.plain" "$WORK/j.plain" \
    || _fail "./sub dir scope differs from the bare sub scope"
echo "ok   ./sub == sub (byte-identical dir scope)"

# a `./`-prefixed FILE arg must keep its base side (no blobAtTree miss →
# false wholly-added: the old `@@ -1,0` shape).
diff_jab "./ file scope" './sub/in.c'
have '^-beta$'     "./ file scope: base side present (not wholly-added)"
have '^\+BETA mod$' "./ file scope: the edit"

pass
