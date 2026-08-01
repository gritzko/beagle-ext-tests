#!/bin/sh
# test/get/line-behind-noop — GET-053 RULING (gritzko 2026-08-01): on a BEHIND
# remote the network leg does NOTHING.  A stale peer advertising an OLDER tip
# on the BARE-get re-fetch is a no-op — objects land, the wt and cur do NOT
# move, no wtlog `get` row, no refusal text.  Fast-backward is a LOCAL motion
# (`#~1`, `?<sha>`), never something a stale server can impose (GET-019 class).
# An EXPLICIT older target over the wire still walks back (test/get/behind-remote).
# RED at GET-053 filing: the bare re-fetch anchors whatever the peer says, so a
# rewound server silently rewinds the worktree.
. "$(dirname "$0")/../../lib/getrepro.sh"

# wire prerequisites (the wirecase.sh idiom): git + passwordless ssh localhost
# + scratch under $HOME (the ssh peer resolves HOME-relative).  SKIP, not FAIL.
[ -z "${BE_TEST_NO_SSH:-}" ] || { echo "SKIP [$NAME] BE_TEST_NO_SSH set"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP [$NAME] no git"; exit 0; }
command -v ssh >/dev/null 2>&1 || { echo "SKIP [$NAME] no ssh"; exit 0; }
case "$WORK" in "$HOME"/*) ;; *) echo "SKIP [$NAME] scratch not under \$HOME"; exit 0 ;; esac
ssh -o BatchMode=yes -o ConnectTimeout=4 localhost true >/dev/null 2>&1 \
    || { echo "SKIP [$NAME] no passwordless ssh to localhost"; exit 0; }

# a green-field remote clone keeps its wtlog INSIDE the `.be` store dir.
rb_wtraw() {
    _f="$1/.be"; [ -f "$1/.be/wtlog" ] && _f="$1/.be/wtlog"
    od -An -c "$_f" 2>/dev/null | tr -d ' \n' | sed 's/\\t//g; s/\\n//g'
}

# a SMALL bare git remote: master@c1, then c2 (a.txt A->A2, +z.txt).
BARE="$WORK/repo.git"; SEED="$WORK/seed"
git init -q --bare -b master "$BARE"
git init -q -b master "$SEED"
git -C "$SEED" config user.email t@e.st; git -C "$SEED" config user.name T
printf 'A\n' > "$SEED/a.txt"
git -C "$SEED" add -A; git -C "$SEED" commit -qm c1
git -C "$SEED" push -q "$BARE" master:master
OLD=$(git -C "$BARE" rev-parse master)
printf 'A2\n' > "$SEED/a.txt"; printf 'Z\n' > "$SEED/z.txt"
git -C "$SEED" add -A; git -C "$SEED" commit -qm c2
git -C "$SEED" push -q "$BARE" master:master
NEW=$(git -C "$BARE" rev-parse master)
[ "$NEW" != "$OLD" ] || _fail "seed did not advance"
REL="${BARE#$HOME/}"

# clone at c2 — the wt now TRACKS the remote's master.
mkdir -p "$WORK/jT"
( cd "$WORK/jT" && "$JABC" get "ssh://localhost/$REL" ) >"$WORK/c.out" 2>"$WORK/c.err" \
    || { cat "$WORK/c.err"; _fail "ssh clone failed"; }
gr_file_is "$WORK/jT/a.txt" "A2"
gr_file_is "$WORK/jT/z.txt" "Z"

# the peer goes STALE: master rewound to c1 (a rewind on the server side).
git -C "$BARE" update-ref refs/heads/master "$OLD"
[ "$(git -C "$BARE" rev-parse master)" = "$OLD" ] || _fail "remote did not rewind"

PRE=$(rb_wtraw "$WORK/jT")

# the assertion: the BARE get re-fetches, sees a BEHIND tip, and does NOTHING.
rc=$(gr_jget "$WORK/jT")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "bare get over a stale peer exit=$rc"; }

# no refusal text (a behind peer is a no-op, not an error).
if grep -qi 'not on this line' "$WORK/last.err"; then
    cat "$WORK/last.err"; _fail "behind peer produced a refusal"
fi
# the wt did not move.
gr_file_is "$WORK/jT/a.txt" "A2"
gr_file_is "$WORK/jT/z.txt" "Z"
# cur did not move: NO new wtlog row at all.
[ "$(rb_wtraw "$WORK/jT")" = "$PRE" ] \
    || { echo "--- wtlog grew ---"; rb_wtraw "$WORK/jT"; echo; \
         _fail "a behind fetched tip still appended a get row"; }

pass
