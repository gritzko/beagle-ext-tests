#!/bin/sh
# test/get/branch-wire — GET-061: `<url>?<branch>` over the WIRE must fetch THAT
# branch or fail BY NAME.  `pickWant` turned a bare `update` into `refs/update`,
# matched nothing (the ref is `refs/heads/update`), and fell into the default
# chain (HEAD sha -> refs/heads/main -> master -> first head) — so the clone got
# MAIN's tip and the wtlog recorded `?update#<main tip>`: a sha under a branch it
# is not on.  Every `?<branch>` fetch resolved by LUCK before this (`?main` only
# looked right because HEAD == main).
#
# Hermetic + OFFLINE: the source is a local be store served by THIS jab
# (`be:<path>/.be` — host-less, POST-028 local exec, no ssh, no network, no
# keeper).  Five legs, all asserting the RECORDED row, not just the checkout:
#   ?update   lands update's OWN tip (u.txt present)         + wtlog `?update#<UPD>`
#   ?main     lands main's tip                               + wtlog `?main#<MAIN>`
#   ?nosuch   fails by NAME, clones NOTHING, leaves NOTHING, and the retry works
#   ?tags/v1  lands the TAG's tip on a be peer               + wtlog `?tags/v1#<VTIP>`
#   bare      the default-branch chain still resolves main   + wtlog `?#<MAIN>`
. "$(dirname "$0")/../../lib/getrepro.sh"

# POST-028: the be: transport spawns the serve peer itself; getrepro pins
# KEEPER_BIN at the RETIRED native keeper, which need not exist — point it at
# jab (what selfBin would pick anyway) so the case never SKIPs on a missing bin.
KEEPER_BIN=$JABC; export KEEPER_BIN

# --- the two-branch source -------------------------------------------------
# c1 on trunk (published: DIS-076, a commit mints no ref), then u1 on ?update.
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt; printf 'B\n' > b.txt
"$BE" post 'c1' >/dev/null 2>&1 || _fail "post c1"
"$BE" post '?'  >/dev/null 2>&1 || _fail "publish trunk"
MAIN=$(gr_tip_sha "$SRC")
[ -n "$MAIN" ] || _fail "no trunk tip"
printf 'U\n' > u.txt
"$BE" put u.txt          >/dev/null 2>&1 || _fail "put u.txt"
"$BE" post '?update' '#u1' >/dev/null 2>&1 || _fail "post ?update"
"$BE" post '?update'       >/dev/null 2>&1 || _fail "publish ?update"
UPD=$(gr_tip_sha "$SRC")
[ -n "$UPD" ] && [ "$UPD" != "$MAIN" ] || _fail "?update did not advance past trunk"

REMOTE="be:$SRC/.be"

# a fresh WIRE clone's `.be` is a store DIR (wtlog inside it) — getrepro's
# gr_wtraw reads the secondary-wt `.be` FILE only, so a dir-aware twin.
bw_wtraw() {
    _f="$1/.be"; [ -f "$1/.be/wtlog" ] && _f="$1/.be/wtlog"
    od -An -c "$_f" 2>/dev/null | tr -d ' \n' | sed 's/\\t//g; s/\\n//g'
}
bw_wtlog_has() {
    bw_wtraw "$1" | grep -qE "$2" \
        || { echo "--- wtlog dump ---"; bw_wtraw "$1"; echo; \
             _fail "wtlog lacks pattern: $2"; }
}

# --- 1. `?update` fetches UPDATE, not the default branch --------------------
mkdir -p "$WORK/upd"
rc=$(gr_jget "$WORK/upd" "$REMOTE?update")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?update exit=$rc"; }
gr_file_is "$WORK/upd/u.txt" "U"               # RED: absent — main has no u.txt
bw_wtlog_has "$WORK/upd" "get\\?update#$UPD"
bw_wtraw "$WORK/upd" | grep -qE "get\\?update#$MAIN" \
    && _fail "recorded ?update against the MAIN tip ($MAIN) — GET-061" || true

# --- 2. `?main` fetches main (the named form keeps working) -----------------
mkdir -p "$WORK/mn"
rc=$(gr_jget "$WORK/mn" "$REMOTE?main")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?main exit=$rc"; }
[ -f "$WORK/mn/u.txt" ] && _fail "?main landed update's tree" || true
bw_wtlog_has "$WORK/mn" "get\\?main#$MAIN"

# --- 3. `?nosuch` fails BY NAME, never a silent default clone ---------------
mkdir -p "$WORK/no"
rc=$(gr_jget "$WORK/no" "$REMOTE?nosuch")
[ "$rc" != 0 ] || _fail "get ?nosuch succeeded — the default branch was substituted"
grep -q 'nosuch' "$WORK/last.err" \
    || { cat "$WORK/last.err"; _fail "the error does not name the missing branch"; }
[ -f "$WORK/no/a.txt" ] && _fail "?nosuch checked the DEFAULT branch out" || true
# the failure is CLEAN: no half-made `.be` (it poisons the obvious retry), and
# no serve-side stack trace over the plain-words error (the peer's courtesy NAK
# hits the hung-up client — a clean end of session, GET-061).
[ -e "$WORK/no/.be" ] && _fail "the failed clone left a half-made .be behind" || true
grep -q 'Broken pipe' "$WORK/last.err" \
    && { cat "$WORK/last.err"; _fail "serve peer dumped a stack over the error"; } || true
# and the RETRY with a real branch works in the very same dir.
rc=$(gr_jget "$WORK/no" "$REMOTE?update")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "retry after the failed clone exit=$rc"; }
gr_file_is "$WORK/no/u.txt" "U"

# --- 4. `?tags/x` over a BE peer resolves the TAG, not the default ----------
# a be store keys a tag as the ref `tags/v1`, and serve.js advertises every key
# through branchlib.wireRef — i.e. as `refs/heads/tags/v1`, which the git form
# `refs/tags/v1` misses.  Same silent-default bug, same cell.
cd "$SRC"
printf 'V\n' > v.txt
"$BE" put v.txt        >/dev/null 2>&1 || _fail "put v.txt"
"$BE" post 'v1'        >/dev/null 2>&1 || _fail "commit v1"
"$BE" post '?tags/v1'  >/dev/null 2>&1 || _fail "publish ?tags/v1"
VTIP=$(gr_tip_sha "$SRC")
[ -n "$VTIP" ] && [ "$VTIP" != "$MAIN" ] || _fail "tag tip setup"
mkdir -p "$WORK/tg"
rc=$(gr_jget "$WORK/tg" "$REMOTE?tags/v1")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?tags/v1 exit=$rc"; }
gr_file_is "$WORK/tg/v.txt" "V"
bw_wtlog_has "$WORK/tg" "get\\?tags/v1#$VTIP"

# --- 5. the empty wantRef still rides the default-branch chain --------------
mkdir -p "$WORK/def"
rc=$(gr_jget "$WORK/def" "$REMOTE")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "bare clone exit=$rc"; }
gr_file_is "$WORK/def/a.txt" "A"
[ -f "$WORK/def/u.txt" ] && _fail "the default clone landed update's tree" || true
bw_wtlog_has "$WORK/def" "get\\?#$MAIN"

pass
