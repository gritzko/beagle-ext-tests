#!/bin/sh
# test/js/parity/loop-color — JAB-025: the resident loop's TTY colour sink.
#
# The loop's emit sink (core/emit.js) gates row colour on `io.isatty(1)` +
# `--color`/`--plain`.  This case proves the THREE-WAY contract WITHOUT a real
# tty (simulating one is unportable — instead drive the colour path explicitly
# via `--color` and the plain path via `--plain`/a pipe, exactly as the ticket
# prescribes):
#
#   (a) REGRESSION GATE — `--plain` (and the default piped run, stdout being a
#       file here so `io.isatty(1)` is false) stay BYTE-IDENTICAL to each other
#       and to today's plain bytes.  The SUT=loop parity sweep redirects stdout,
#       so EVERY parity case hits this same plain path — if it changed, those
#       would byte-diff.  Here we re-assert it directly: default-pipe == --plain.
#
#   (b) COLOUR — `--color` forces the binding's C-THEME `.color` render of the
#       columnar rows: the output carries an ESC (27 / \033) SGR escape that the
#       plain output never does, and so DIFFERS from plain.  (Modelled on
#       test/js/bro/table, which already asserts `.color` carries SGR.)
#
# This case only exercises the JS loop (no native oracle leg) — it gates the
# loop's OWN plain-vs-colour split, not native byte-parity (the rest of the
# parity sweep gates that).  SUT is pinned to `loop` regardless of the caller's
# selector (the colour path lives only in the loop entry).
SUT=loop
. "$(dirname "$0")/../../lib/parity.sh"

# A committed baseline + a dirty tree (a tracked mod + an untracked add) so the
# status block carries real columnar rows to colourise.
seed_baseline 'printf "A\n" > a.txt; printf "B\n" > b.txt; mkdir d; printf "C\n" > d/c.txt'
fork_pair
mutate() { ( cd "$JS" && eval "$1" ); }   # JS-side only (no native fork here)
mutate 'sleep 0.02; printf "A2\n" > a.txt; printf "N\n" > n.txt'

# Drive the loop three ways in the JS fork.  run_js resolves $BEDIR/loop.js.
( cd "$JS" && run_js status          ) >"$WORK/pipe.out"  2>"$WORK/pipe.err" || true
( cd "$JS" && run_js status --plain  ) >"$WORK/plain.out" 2>"$WORK/plain.err" || true
( cd "$JS" && run_js status --color  ) >"$WORK/color.out" 2>"$WORK/color.err" || true

# (a) REGRESSION: the default piped run and `--plain` are byte-identical (the
#     plain path is untouched — no date-column normalisation needed, same run).
cmp -s "$WORK/pipe.out" "$WORK/plain.out" || {
    echo "--- pipe ---";  cat -A "$WORK/pipe.out"
    echo "--- plain ---"; cat -A "$WORK/plain.out"
    _fail "default-pipe and --plain differ (plain path not byte-stable)"
}
# The plain path must carry NO SGR escape (byte-parity plain).
if LC_ALL=C grep -q "$(printf '\033')" "$WORK/plain.out"; then
    echo "--- plain ---"; cat -A "$WORK/plain.out"
    _fail "--plain carries an SGR escape (should be byte-parity plain)"
fi
echo "ok: default-pipe == --plain, no SGR (plain path byte-stable)"

# (b) COLOUR: --color carries an ESC (27) SGR escape and DIFFERS from plain.
LC_ALL=C grep -q "$(printf '\033')" "$WORK/color.out" || {
    echo "--- color ---"; cat -A "$WORK/color.out"
    _fail "--color carries NO SGR escape (colour sink not engaged)"
}
cmp -s "$WORK/color.out" "$WORK/plain.out" && {
    echo "--- color == plain ---"; cat -A "$WORK/color.out"
    _fail "--color is byte-identical to --plain (no colour applied)"
}
echo "ok: --color carries SGR (ESC 27) and differs from plain"

pass
