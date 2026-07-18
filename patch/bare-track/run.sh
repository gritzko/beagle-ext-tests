#!/bin/sh
# PATCH spec 2026-07-17: RED until bare `jab patch` absorbs the tracked ref's line
#
# test/patch/bare-track — PATCH.mkd §Shapes: "?<ref> (or bare patch = the
# tracked ref): absorb every missing commit of that line".  Fixture: ONE
# primary wt; trunk t0 -> t1 -> t2 (the ref republished per commit via
# `post ?`), then the wt is PINNED back at t1 (`get ?#t1`) — the tracked
# (attached) trunk ref now sits one commit AHEAD of cur.  Bare `jab patch`
# must absorb t2's edit into the wt and record the absorption row.
#
# TODAY (code audit + probe): patchscope.resolveOurs reads OURS from the
# branch REF (reader.resolveRef) rather than the wt's own cur tip, so
# ours == theirs == t2, the missing set reads empty and bare patch does
# NOTHING — exit 0, no bytes, no row.  Spec-first: assert the ruling.
. "$(dirname "$0")/../../lib/patchspec.sh"

ORG="$WORK/org"; mkdir -p "$ORG/.be"
cd "$ORG"
printf 'f base\n' > f.txt
printf 'g base\n' > g.txt
_boot 't0'; T0=$BOOT
printf 'f t1\n' > f.txt; _ci 't1 f' f.txt
T1=$(_tip)
printf 'g t2\n' > g.txt; _ci 't2 g' g.txt
T2=$(_tip)
[ "$T1" != "$T2" ] || _fail "builder: trunk did not advance"

#  Pin the wt back one commit: cur = t1, tracked trunk ref stays at t2.
_jab get "?#$T1" >/dev/null 2>&1
[ "$(_orgtip .)" = "$T1" ]   || _fail "pin-back failed (cur != t1)"
[ "$(cat g.txt)" = "g base" ] || _fail "pin-back left g.txt: $(cat g.txt)"

#  THE SPEC POINT: bare patch = `patch ?<tracked>` — absorb the whole missing
#  line (here: t2), land its bytes, record the patch row for the next post.
_jab patch > "$WORK/p.out" 2> "$WORK/p.err" \
    || _fail "bare patch exited non-zero: $(cat "$WORK/p.err")"
[ "$(cat g.txt)" = "g t2" ] \
    || { echo "--- stdout ---"; cat "$WORK/p.out"; \
         _fail "bare patch absorbed NOTHING (g.txt: '$(cat g.txt)', want 'g t2')"; }
[ "$(cat f.txt)" = "f t1" ] || _fail "bare patch touched f.txt: $(cat f.txt)"
ps_patch_rows "$ORG" | grep -q "$T2" \
    || { echo "--- wtlog rows ---"; ps_patch_rows "$ORG"; \
         _fail "no patch row recording the absorbed line tip ($T2)"; }

pass
