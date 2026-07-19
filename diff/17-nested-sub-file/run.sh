#!/bin/sh
# DIFF-014 regression: `jab diff <sub>/<sub2>/<file>` — a file under a NESTED
# mount (two levels deep).  DIFF-011 made the scoped wt+path diff mount-aware,
# but subMountSplit split only ONE level: the from-side read then dead-ended at
# the inner gitlink and the file rendered wholly-added (`@@ -1,0 ...`).  A file
# TWO subs deep (par -> dog -> abc) must read its baseline from the DEEPEST sub,
# byte-identical to the in-sub `cd dog/abc && jab diff FILE.h`.  The dir-scoped
# path already recursed nesting; the single-file scope now does too.
. "$(dirname "$0")/../lib/diffcase.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git not found" >&2; exit 0; }
git_ssh_ok || { echo "SKIP: no git/ssh-to-localhost for the git-wire ingest" >&2; exit 0; }
case "$WORK" in "$HOME"/*) ;; *) echo "SKIP: scratch not under \$HOME (git-over-ssh)" >&2; exit 0 ;; esac
export GIT_CONFIG_GLOBAL=/dev/null

S="$WORK/git"; rm -rf "$S"; mkdir -p "$S"; cd "$S"
mkg() {
    git init -q -b master "$1" >/dev/null 2>&1 || return 1
    git -C "$1" config user.email t@t
    git -C "$1" config user.name  T
    git -C "$1" config protocol.file.allow always
}

# leaf `abc` (a multi-line file so the diff has context), mid `dog` pinning it,
# parent `par` pinning `dog` — so `abc` sits TWO gitlinks below `par`.
mkg abc || { echo "FAIL(setup): git init abc" >&2; exit 1; }
printf 'l1\nl2\nl3\nl4\nl5\nl6\n' > abc/FILE.h
git -C abc add -A; git -C abc commit -qm a1
mkg dog || { echo "FAIL(setup): git init dog" >&2; exit 1; }
printf 'dog\n' > dog/d.txt
git -C dog -c protocol.file.allow=always submodule add -q "$S/abc" abc >/dev/null 2>&1 \
    || { echo "FAIL(setup): submodule add abc" >&2; exit 1; }
git_submodule_url dog abc "$S/abc" >/dev/null
git -C dog add -A; git -C dog commit -qm d1
mkg par || { echo "FAIL(setup): git init par" >&2; exit 1; }
printf 'par\n' > par/p.txt
git -C par -c protocol.file.allow=always submodule add -q "$S/dog" dog >/dev/null 2>&1 \
    || { echo "FAIL(setup): submodule add dog" >&2; exit 1; }
git_submodule_url par dog "$S/dog" >/dev/null
git -C par add -A; git -C par commit -qm p1

# import over the GIT WIRE into a PRIMARY store — mounts BOTH nesting levels.
git_ingest "$S/par" par "$S/B1" >/dev/null \
    || { echo "FAIL(setup): git-wire ingest of par into B1" >&2; exit 1; }
cd "$S/B1"
[ -f dog/.be ]     || { echo "FAIL: dog not mounted" >&2; exit 1; }
[ -f dog/abc/.be ] || { echo "FAIL: dog/abc (nested) not mounted" >&2; exit 1; }

# dirty the file INSIDE the DEEPEST sub (inline + whole-line change).
printf 'l1\nCHANGED2\nl3\nl4\nl5\nl6\n' > dog/abc/FILE.h

# (1) parent-root FILE scope: a real inline diff, NOT wholly-added.
diff_jab "wt-vs-base of a file under a NESTED mount" 'dog/abc/FILE.h'
have '^\+CHANGED2'  "nested file: the added line"
have '^-l2'         "nested file: the removed line (real diff, not addition)"
miss '@@ -1,0 '     "nested file: NOT wholly-added (empty baseline)"

# (2) byte-parity: parent-root scope == in-sub scope (strip the mount prefix).
sed 's#a/dog/abc/#a/#;s#b/dog/abc/#b/#' "$WORK/j.plain" > "$WORK/root.plain"
( cd dog/abc && "$JABC" diff FILE.h --plain ) > "$WORK/insub.plain" 2>/dev/null
cmp -s "$WORK/root.plain" "$WORK/insub.plain" \
    || { echo "--- root ---"; cat "$WORK/root.plain"; echo "--- insub ---"; cat "$WORK/insub.plain"; _fail "nested file: parent-root vs in-sub NOT byte-identical"; }
echo "ok   nested file byte-parity (root == in-sub)"

# (3) <sub>/<dir> scope reaches the nested file too.
diff_jab "dir scope over a nested mount" 'dog/abc'
have 'dog/abc/FILE.h' "nested dir scope: the file appears"

# (4) an UNTOUCHED file under the nested mount diffs EMPTY, not wholly-added.
printf 'l1\nl2\nl3\nl4\nl5\nl6\n' > dog/abc/FILE.h
_z=0; "$JABC" diff dog/abc/FILE.h --plain > "$WORK/j.clean" 2>/dev/null || _z=$?
[ "$_z" = 0 ] || _fail "clean nested file: jab diff exited nonzero"
[ -s "$WORK/j.clean" ] && { echo "--- unexpected ---"; cat "$WORK/j.clean" | head; _fail "clean nested file: expected EMPTY, got a diff"; }
echo "ok   untouched nested file diffs empty"

pass
