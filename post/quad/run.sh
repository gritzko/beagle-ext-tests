#!/bin/sh
# BRO-030 test/post/quad — the unified quad status report is now the DEFAULT
# `jab post` banner (wiki/Status.mkd; no flag).  Fixture (the commit-ahead
# shape): c1 commits a.txt, publish + track ?feat, then stage a modified a.txt
# + a new n.txt and `post '#c2'`.  The banner must carry the PRE-post quad rows
# for the committed set ("what got absorbed": the put-staged mod a.txt is
# `...V`, the staged add n.txt is `...O`) and, after the commit, the `.o..`
# divergence row of the new local commit vs the still-at-c1 track.
. "$(dirname "$0")/../../lib/postcase.sh"

# Fixture: c1 (a.txt), publish ?feat at c1, track it.
A="$WORK/a"; mkdir -p "$A/.be"
( cd "$A" && printf 'one\n' > a.txt && "$JABC" post '#c1' ) >/dev/null 2>&1 \
    || _fail "bootstrap post c1 failed"
( cd "$A" && "$JABC" post '?feat' ) >/dev/null 2>&1 \
    || _fail "publish ?feat failed"
( cd "$A" && "$JABC" get '?feat' ) >/dev/null 2>&1 \
    || _fail "switch to track ?feat failed"

# one modified + one created file, both staged.
printf 'two\n' > "$A/a.txt"
printf 'new\n' > "$A/n.txt"
( cd "$A" && "$JABC" put a.txt n.txt ) >/dev/null 2>&1 || _fail "put failed"

( cd "$A" && "$JABC" post '#c2' ) >"$WORK/q.out" 2>"$WORK/q.err" \
    || _fail "post failed: $(cat "$WORK/q.err")"

# BRO-030: the PRE-post quad rows for the committed files (`<date7> <quad4>
# <path>`), ASCII canon; staged wt char is UPPERCASE (put-staged).
grep -Eq '\.\.\.V a\.txt$' "$WORK/q.out" \
    || _fail "no ...V quad row for the staged-modified a.txt: $(cat "$WORK/q.out")"
grep -Eq '\.\.\.O n\.txt$' "$WORK/q.out" \
    || _fail "no ...O quad row for the staged-created n.txt: $(cat "$WORK/q.out")"
# the post-commit divergence: the new local commit as ".o.." vs the track.
grep -Eq '\.o\.\. \?[0-9a-f]{8}#c2$' "$WORK/q.out" \
    || _fail "no .o.. commit divergence row: $(cat "$WORK/q.out")"
# the legacy per-file confirmation rows have retired under the quad default.
grep -q 'mod a\.txt' "$WORK/q.out" \
    && _fail "quad default still prints the legacy mod row" || true

pass
