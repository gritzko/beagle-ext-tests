#!/bin/sh
# test/sub/bareput-scope — PUT-008: a bare `jab put` run from a SUBDIR cwd must
# SCOPE to that subtree (be.ctxDir via discover.ctxSub) — stage only the tracked-
# dirty set at/below the dir and recurse ONLY mounted subs at/below it.  Before
# the fix bareStage + bareStageSubs ignored the cwd and staged the WHOLE wt plus
# every mounted sub.  Legs: (a) bare put from app/ stages app/ ONLY — a dirty
# ROOT file and the dirty mounted-sub file (both OUTSIDE app/) stay UNSTAGED
# [RED before the fix]; (b) bare put from the wt ROOT stays whole-wt incl. sub
# descent (regression); (c) explicit `put app` unchanged (regression).
#
# TEST-003 FLAGGED: needs the JS-keeper feature — the mounted sub CHILD is
# fetched over the git/keeper WIRE (submount.mount), no keeper-free local path.
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent

# Add a tracked parent subdir file `app/feature.c` to the parent baseline — the
# scope dir; a dirtied copy is then tracked-dirty UNDER app/ (in scope).
( cd "$PARSTORE" && mkdir -p app && printf 'v1\n' > app/feature.c \
    && "$BE" put app/feature.c >/dev/null 2>&1 && "$BE" post '#add app' >/dev/null 2>&1 ) \
    || _fail "seed app/feature.c into the parent baseline"

# setup DST — fresh clone of the parent (mounts the sub), then dirty three spots:
# a ROOT parent file, an app/ parent file (in scope), and a SUB-interior file.
setup() {
    sc_jget "$1" "file://$PARSTORE/.be" >/dev/null
    [ -f "$1/vendor/sub/lib.c" ] || _fail "$1: sub not mounted/checked out"
    [ -f "$1/app/feature.c" ]    || _fail "$1: app/feature.c not checked out"
    printf 'ROOT edited\n' > "$1/main.c"            # parent ROOT mod (OUTSIDE app/)
    printf 'APP edited\n'  > "$1/app/feature.c"     # parent app/ mod (IN scope)
    printf 'SUB edited\n'  > "$1/vendor/sub/lib.c"  # sub-interior mod (OUTSIDE app/)
}

# ---- leg (a): bare put from app/ scopes to app/ [RED before the fix] ----
A="$WORK/a"; setup "$A"
( cd "$A/app" && "$JABC" put ) >"$A.out" 2>"$A.err" || true
grep -qE 'put[[:space:]]+app/feature\.c' "$A/.be" \
    || _fail "a: app/feature.c not staged from the app/ cwd: $(cat "$A/.be")"
grep -qE 'put[[:space:]]+main\.c' "$A/.be" \
    && _fail "a: ROOT main.c staged from the app/ cwd (whole-wt leak)"
grep -qE 'put[[:space:]]+lib\.c' "$A/vendor/sub/.be" \
    && _fail "a: sub lib.c staged from the app/ cwd (sub-recursion leak)"
echo "ok   (a) bare put @app/ scopes to app/ — the root + sub stay unstaged"

# ---- leg (b): bare put from the wt ROOT stays whole-wt + sub descent ----
B="$WORK/b"; setup "$B"
( cd "$B" && "$JABC" put ) >"$B.out" 2>"$B.err" || true
grep -qE 'put[[:space:]]+main\.c'        "$B/.be" || _fail "b: root main.c not staged (whole-wt)"
grep -qE 'put[[:space:]]+app/feature\.c' "$B/.be" || _fail "b: app/feature.c not staged (whole-wt)"
grep -qE 'put[[:space:]]+lib\.c' "$B/vendor/sub/.be" || _fail "b: sub lib.c not staged (sub descent)"
echo "ok   (b) bare put @root stays whole-wt incl. sub descent"

# ---- leg (c): explicit `put app` unchanged (scopes to app/, no sub) ----
C="$WORK/c"; setup "$C"
( cd "$C" && "$JABC" put app ) >"$C.out" 2>"$C.err" || true
grep -qE 'put[[:space:]]+app/feature\.c' "$C/.be" || _fail "c: app/feature.c not staged by put app"
grep -qE 'put[[:space:]]+main\.c'        "$C/.be" && _fail "c: main.c staged by put app"
echo "ok   (c) explicit put app unchanged"

pass
