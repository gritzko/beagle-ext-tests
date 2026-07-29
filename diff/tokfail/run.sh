#!/bin/sh
# test/diff/tokfail — DIFF-015: a tokenizer failure must NOT erase a changed
# file from `diff`.  Every `weave.fold` failure reaches JS as the ONE string
# "weave.fold: failed (out full?)" (jab/weave.hpp:189), and diff.js swallowed
# anything containing "full" as the over-cap blob-skip — so a file whose bytes
# derail the lexer (DOG-021: a `/` inside a regex char class) vanished from the
# diff with exit 0 while `status` still listed it dirty.  The fix refolds under
# libdog's plain-text lexer (ext "") and says so in plain words.
#
# Two legs.  (1) a jab unit over the worktree's views/diff/diff.js that STUBS
# the lexed fold to throw — durable, since it does not depend on ANY input
# still breaking the native lexer once DOG-021's grammar fix lands.  (2) the
# end-to-end invariant over the real `jab diff` path: a tracked file carrying
# the poison regex, edited in the wt, MUST show its change (whichever lexer
# renders it).  Picked up by the test/CMakeLists `*/*/run.sh` glob as
# be-js-diff-tokfail (NO CMakeLists edit).
. "$(dirname "$0")/../lib/diffcase.sh"

# --- leg 1: the stubbed-fold unit (no store needed) -------------------------
# The unit lives IN the be/ tree, so jab's upward be/-scan resolves its
# be-relative require("views/diff/diff.js") (the diff/links unit pattern).
# A failed assert THROWS → non-zero exit; io.log lands on stderr, so keep both.
_rc=0
"$JABC" "$_CASE/tokfail.js" >"$WORK/unit.log" 2>&1 || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/unit.log"; _fail "tokfail.js exited non-zero ($_rc)"; }
grep -q 'tokfail.js OK' "$WORK/unit.log" || { cat "$WORK/unit.log"
    _fail "tokfail.js did not report OK"; }
# The plain-words notice rides the fallback (never a bare C code like JSTBAD).
grep -q 'cannot tokenize f.js .* plain text' "$WORK/unit.log" \
    || { cat "$WORK/unit.log"; _fail "no plain-words 'cannot tokenize' notice"; }
echo "ok   fold failure refolds under the plain lexer (+ notice)"

# --- leg 2: end-to-end — a changed file NEVER disappears --------------------
W=$(new_wt p)
cd "$W"
# DOG-021's poison: a regex literal whose char class holds `/`, plus a quote in
# the tail — JST ends the literal early and runs a string to EOF (JSTBAD).
cat > poison.js <<'EOJS'
"use strict";
const RULES = [
  { re: /[[\]()!*_~|\\:.\-+#&<>{}=,;/'"@^`]/y, tag: "P" },
];
module.exports = RULES;
EOJS
# TEST-003: bare bootstrap post (a leading `jab put` corrupts the bootstrap).
"$BE" post -m v1 '?trunk' >/dev/null 2>&1
"$BE" post '?trunk' >/dev/null 2>&1

printf '//  TOKFAIL-VISIBLE-EDIT-MARKER\n' >> poison.js
# `status` calls it dirty; `diff` MUST agree (pre-fix: zero bytes, exit 0).
"$BE" status poison.js 2>/dev/null | grep -q 'poison.js' \
    || _fail "status does not see the wt edit (fixture broken)"
diff_jab "wt diff of a lexer-hostile file" poison.js
have '^--- a/poison.js' "the changed file keeps its diff header"
have 'TOKFAIL-VISIBLE-EDIT-MARKER' "the changed line is rendered"
echo "ok   a changed file never disappears from the wt diff"

pass
