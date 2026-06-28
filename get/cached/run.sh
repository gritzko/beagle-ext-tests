#!/bin/sh
# test/get/cached — DIS-055 D7: `be get //host?branch` reads the CACHED store
# tip with NO network — only a transport scheme (ssh:/be:) opens the wire.
# GET.mkd pt 4: "Host: remote to fetch from (uses the cached tip if no scheme
# set)".  Setup needs a be:// clone (writes a remote-tracking row) — that is
# the same ssh-to-localhost path the be-clone case uses (gated WITH_SSH); skip
# cleanly if it is unavailable.
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt; printf 'B\n' > b.txt
"$BE" post 'c1' >/dev/null 2>&1
case "$SRC" in "$HOME"/*) RELBE="${SRC#$HOME/}/.be" ;;
    *) echo "SKIP [cached] scratch not under \$HOME"; exit 0 ;; esac

# be:// clone — writes a `get be://localhost/...?#<tip>` remote-tracking row.
mkdir "$WORK/jT"; cd "$WORK/jT"
"$JABC" get "be://localhost/$RELBE?/src" >/dev/null 2>"$WORK/clone.err" || true
[ -f "$WORK/jT/a.txt" ] || { echo "SKIP [cached] no be:// clone (ssh?)"; \
    cat "$WORK/clone.err" >&2; exit 0; }

# Remove a tracked file, then `be get //localhost?` must restore it from the
# CACHED tip with NO network (no ssh/keeper spawn).  Block both transports so a
# wire attempt FAILS loudly: point SSH_BIN/KEEPER_BIN at /bin/false — a cached
# read never invokes either.
rm -f "$WORK/jT/a.txt"
rc=0
( cd "$WORK/jT" && SSH_BIN=/bin/false KEEPER_BIN=/bin/false \
    "$JABC" get "//localhost?" ) >"$WORK/last.out" 2>"$WORK/last.err" || rc=$?
[ "$rc" = 0 ] || { echo "--- err ---"; cat "$WORK/last.err"; \
    _fail "//localhost? cached read exit=$rc (spawned the wire?)"; }
gr_file_is "$WORK/jT/a.txt" "A"      # restored from the cached tip

pass
