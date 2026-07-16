#!/bin/sh
# test/get/detach — DIS-055 D2: `be get ?<sha>` detaches at that commit and
# writes the detached wtlog row (`?<40hex>` in the query, empty fragment — the
# shape post.js's detached guard recognises).  GET.mkd pt 3: "a bare sha
# detaches (will stay detached on commit)".
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
gr_jclone "$SRC" "$WORK/jT"
TIP=$(gr_tip_sha "$SRC")
[ -n "$TIP" ] || _fail "no tip sha"

# Make a second commit so cur != older sha would be observable; but the detach
# target IS the trunk tip here — assert the detached ROW shape, not movement.
rc=$(gr_jget "$WORK/jT" "?$TIP")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?<sha> exit=$rc"; }

# The wt must still carry the tree (a.txt present).
gr_file_is "$WORK/jT/a.txt" "A"

# DIS-075: `?<sha>` is the ARGUMENT; the RECORD is `#<40hex>` — sha in the
# FRAGMENT, query slot ABSENT (nothing is tracked, so nothing is queried).
gr_wtlog_has "$WORK/jT" "get#$TIP"
# And NOT `?#<sha>`: a PRESENT-empty query is the TRUNK shape (attached).
gr_wtraw "$WORK/jT" | grep -qE "get\\?#$TIP\$" \
    && _fail "detach wrote the trunk-shaped ?#<sha> row, not the detached #<sha>" || true

# Short-hex detach must work too (D2: full OR short hex) — the short ARGUMENT
# still records the resolved FULL sha as the detached `#<40hex>` record.
SHORT=$(printf '%s' "$TIP" | cut -c1-10)
rc=$(gr_jget "$WORK/jT" "?$SHORT")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?<shorthex> exit=$rc"; }
gr_wtlog_has "$WORK/jT" "get#$TIP"

pass
