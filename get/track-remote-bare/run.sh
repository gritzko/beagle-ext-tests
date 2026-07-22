#!/bin/sh
# test/get/track-remote-bare — GET-047 / GET.mkd 1.1 + 1.6: a bare `jab get`
# in a wt cloned off a REMOTE implies the tracked ref — the recentmost get
# record's track resolves back to the remote (case 6), so the bare get
# re-fetches over the wire and lands the advanced tip, NO URL re-passed
# (every existing update test re-passes the ssh:/http: URL explicitly).
#
# MISMATCH at tip fe042740 (hence run.sh.broken, not registered): the clone
# records only `?master#<tip>` in the wtlog (the remote URL lives store-side),
# and inRepoSeed resolves the branch in the LOCAL store only — no wire leg.
# Observed after advancing the ssh remote (master -> cec4798d..., new z.txt):
#   bare get rc=0, z.txt absent, a.txt stays "A", wtlog appends the SAME OLD
#   `get?master#5d27ac4e...` row — a silent stale no-op instead of a re-fetch.
. "$(dirname "$0")/../../lib/getrepro.sh"

# wire prerequisites (the wirecase.sh idiom): git + passwordless ssh localhost
# + scratch under $HOME (the ssh peer resolves HOME-relative).  SKIP, not FAIL.
# BE_TEST_NO_SSH=1 force-skips ssh cases (CI); see wire/lib/wirecase.sh.
[ -z "${BE_TEST_NO_SSH:-}" ] || { echo "SKIP [$NAME] BE_TEST_NO_SSH set"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP [$NAME] no git"; exit 0; }
command -v ssh >/dev/null 2>&1 || { echo "SKIP [$NAME] no ssh"; exit 0; }
case "$WORK" in "$HOME"/*) ;; *) echo "SKIP [$NAME] scratch not under \$HOME"; exit 0 ;; esac
ssh -o BatchMode=yes -o ConnectTimeout=4 localhost true >/dev/null 2>&1 \
    || { echo "SKIP [$NAME] no passwordless ssh to localhost"; exit 0; }

# a remote clone is GREEN-FIELD: `.be` is a store DIR, the wtlog a file inside
# it — getrepro's gr_wtraw reads the secondary-wt `.be` FILE only, so a local
# dir-aware twin.
rb_wtraw() {
    _f="$1/.be"; [ -f "$1/.be/wtlog" ] && _f="$1/.be/wtlog"
    od -An -c "$_f" 2>/dev/null | tr -d ' \n' | sed 's/\\t//g; s/\\n//g'
}
rb_wtlog_has() {
    rb_wtraw "$1" | grep -qE "$2" \
        || { echo "--- wtlog dump ---"; rb_wtraw "$1"; echo; \
             _fail "wtlog lacks pattern: $2"; }
}

# a SMALL bare git remote: master@c1 (a.txt=A).
BARE="$WORK/repo.git"; SEED="$WORK/seed"
git init -q --bare -b master "$BARE"
git init -q -b master "$SEED"
git -C "$SEED" config user.email t@e.st; git -C "$SEED" config user.name T
printf 'A\n' > "$SEED/a.txt"
git -C "$SEED" add -A; git -C "$SEED" commit -qm c1
git -C "$SEED" push -q "$BARE" master:master
REL="${BARE#$HOME/}"
OLD=$(git -C "$BARE" rev-parse master)

# clone over the wire — the wt now TRACKS the remote's master.
mkdir -p "$WORK/jT"
( cd "$WORK/jT" && "$JABC" get "ssh://localhost/$REL" ) >"$WORK/c.out" 2>"$WORK/c.err" \
    || { cat "$WORK/c.err"; _fail "ssh clone failed"; }
gr_file_is "$WORK/jT/a.txt" "A"
rb_wtlog_has "$WORK/jT" "\\?master#$OLD"

# advance the REMOTE: c2 (a.txt=A2, +z.txt) pushed to master.
printf 'A2\n' > "$SEED/a.txt"; printf 'Z\n' > "$SEED/z.txt"
git -C "$SEED" add -A; git -C "$SEED" commit -qm c2
git -C "$SEED" push -q "$BARE" master:master
NEW=$(git -C "$BARE" rev-parse master)
[ "$NEW" != "$OLD" ] || _fail "remote did not advance"

# the assertion: BARE `jab get` (no URL) re-resolves the tracked remote,
# fetches, and lands the new tip.
rc=$(gr_jget "$WORK/jT")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "bare get exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A2"
gr_file_is "$WORK/jT/z.txt" "Z"
rb_wtlog_has "$WORK/jT" "\\?master#$NEW"

pass
