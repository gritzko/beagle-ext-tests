#!/bin/sh
# test/get/traversal — JS-065 path-traversal guard.  A malicious git tree
# whose entry named `..` carries `evil.txt` makes the leaf path `../evil.txt`;
# unguarded `jab get` writes it OUTSIDE the worktree.  Assert the JS get ERRORS
# and writes/unlinks NOTHING above the wt, while a sibling clean tree still
# checks out.  Needs git + ssh-to-localhost (same transport as get/git).
. "$(dirname "$0")/../../lib/getcase.sh"

# Reaches ssh://localhost once scratch is under $HOME (true on CI runners and dev
# boxes), so gate on ssh up-front — BE_TEST_NO_SSH=1 force-skips (CI; see
# wire/lib/wirecase.sh), and a passwordless-ssh probe skips cleanly when sshd is
# down.  Otherwise a refused connect FAILs the guard assertion instead of SKIPing.
[ -z "${BE_TEST_NO_SSH:-}" ] || { echo "SKIP [traversal] BE_TEST_NO_SSH set"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP [traversal] no git"; exit 0; }
command -v ssh >/dev/null 2>&1 || { echo "SKIP [traversal] no ssh"; exit 0; }
ssh -o BatchMode=yes -o ConnectTimeout=4 localhost true >/dev/null 2>&1 \
  || { echo "SKIP [traversal] no passwordless ssh to localhost"; exit 0; }

# --- build the malicious repo via git plumbing (a `..` tree entry can NOT be
# created from a checked-out worktree; mktree takes the name verbatim) --------
REPO="$WORK/evil"
mkdir -p "$REPO"; cd "$REPO"
git init -q; git config user.email t@e.st; git config user.name T
GOOD=$(printf 'good\n' | git hash-object -w --stdin)
PWN=$(printf 'PWNED-by-traversal\n' | git hash-object -w --stdin)
# subtree named ".." holding evil.txt  ->  flattened leaf path "../evil.txt"
SUB=$(printf '100644 blob %s\tevil.txt\n' "$PWN" | git mktree)
ROOT=$(printf '100644 blob %s\tok.txt\n040000 tree %s\t..\n' "$GOOD" "$SUB" \
       | git mktree)
EVIL=$(printf 'malicious\n' | git commit-tree "$ROOT")
git update-ref refs/heads/master "$EVIL"

case "$REPO" in
    "$HOME"/*) RELEVIL="${REPO#$HOME/}" ;;
    *) echo "SKIP [traversal] scratch not under \$HOME"; exit 0 ;;
esac

# jT/ is the worktree; ../evil.txt from inside it lands in $WORK (a SENTINEL
# there must stay untouched, and no PWNED file may appear above the wt).
JT="$WORK/jT"; mkdir -p "$JT"
printf 'SENTINEL\n' > "$WORK/sentinel.txt"

( cd "$JT" && "$JABC" get "ssh://localhost/$RELEVIL?/evil" ) \
    >"$WORK/jT.out" 2>"$WORK/jT.err" && \
    _fail "malicious get SUCCEEDED (expected an error)"

# the leaf path "../evil.txt" must never have been written above the wt
[ -f "$WORK/evil.txt" ] && _fail "ESCAPE: wrote ../evil.txt outside the wt"
cmp -s "$WORK/sentinel.txt" - <<EOF || _fail "ESCAPE: sentinel clobbered"
SENTINEL
EOF
grep -q "unsafe path" "$WORK/jT.out" "$WORK/jT.err" || \
    _fail "no guard error emitted: $(cat "$WORK/jT.err")"

# --- a clean sibling tree still checks out fine -----------------------------
CLEAN="$WORK/clean"
mkdir -p "$CLEAN"; cd "$CLEAN"
git init -q; git config user.email t@e.st; git config user.name T
printf 'A\n' > a.txt; mkdir d; printf 'C\n' > d/c.txt
git add -A; git commit -qm c1
case "$CLEAN" in "$HOME"/*) RELCLEAN="${CLEAN#$HOME/}" ;; esac

CT="$WORK/cT"; mkdir -p "$CT"
( cd "$CT" && "$JABC" get "ssh://localhost/$RELCLEAN?/clean" ) >/dev/null 2>&1 \
    || _fail "clean get FAILED"
[ -f "$CT/a.txt" ] && [ -f "$CT/d/c.txt" ] || _fail "clean tree not materialised"

pass
