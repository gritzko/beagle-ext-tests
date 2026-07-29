//  test/diff/tokfail/tokfail.js — DIFF-015 repro: a fold failure must NEVER
//  erase a changed file from the diff.  The jab binding collapses EVERY
//  `weave.fold` failure into the ONE string `weave.fold: failed (out full?)`
//  (jab/weave.hpp:189) — an over-cap markup buffer AND a tokenizer derail
//  (DOG-021's `/` inside a regex char class → JSTBAD) read identical.  diff.js
//  swallowed anything containing "full" as the over-cap blob-skip, so the file
//  vanished: no header, no hunk, exit 0, while `status` still called it dirty.
//
//  The fix retries the SAME fold with ext "" (libdog's TXTT plain-text lexer,
//  which tokenises any bytes) and only then skips.  This unit STUBS the lexed
//  fold to throw — so it stays a live repro after DOG-021's grammar fix lands
//  and the poison regex stops failing natively (the durable invariant is "a
//  changed file never disappears", not "this one regex breaks JST").
//    RED  (pre-fix): leg 2 emits ZERO bytes — the file disappeared.
//    GREEN: leg 2 emits the `--- a/f.js` header + the changed lines, refolded
//           under ext "" (leg 2b), a genuine always-fail still blob-skips (3),
//           and a non-"full" error still propagates (4).

"use strict";

const { eq, ok, fail, throws } = require("../../lib/assert.js");
const weave = require("shared/weave.js");
const diff = require("views/diff/diff.js");

const FROM = utf8.Encode("alpha\nbeta\ngamma\n");
const TO   = utf8.Encode("alpha\nBETA\ngamma\n");
const NAME = "f.js";

//  Collect the rendered plain text of one diffFile run.
function run() {
  let text = "";
  diff.diffFile(NAME, FROM, TO, true, "", false,
                { chunk: function (s) { text += s; } });
  return text;
}

//  Swap weave.fold for `fn` (diff.js calls it THROUGH the module object, so a
//  property swap intercepts it); returns the original for restore.
const realFold = weave.fold;
let exts = [];
function stub(fn) { exts = []; weave.fold = fn; }
function unstub() { weave.fold = realFold; }

//  --- 1. control: an unstubbed, healthy fold renders hunks ------------------
const good = run();
ok(good.indexOf("--- a/" + NAME) >= 0, "control: the diff header renders");
ok(good.indexOf("+BETA") >= 0, "control: the changed line renders");

//  --- 2. a lexed fold that fails must refold under the PLAIN lexer ----------
//  Exactly DOG-021's shape: ext "js" throws the masked message, ext "" folds.
stub(function (base, blob, ext, hash) {
  exts.push(ext);
  if (ext !== "") throw "weave.fold: failed (out full?)";
  return realFold(base, blob, ext, hash);
});
const fallback = run();
unstub();
ok(fallback.length > 0, "DIFF-015: a fold failure does NOT erase the file");
ok(fallback.indexOf("--- a/" + NAME) >= 0, "DIFF-015: the header still renders");
ok(fallback.indexOf("+BETA") >= 0, "DIFF-015: the changed line still renders");
//  2b. the retry really is the plain-text lexer, not another lexed attempt.
eq(exts[0], "js", "DIFF-015: the first fold uses the file's own lexer");
ok(exts.indexOf("") >= 0, "DIFF-015: the retry folds under ext \"\" (TXTT)");

//  --- 3. a GENUINE over-cap (even "" overflows) still blob-skips ------------
stub(function (base, blob, ext, hash) {
  exts.push(ext);
  throw "weave.fold: failed (out full?)";
});
let overcap;
try { overcap = run(); } catch (e) { unstub(); fail("over-cap must not throw: " + e); }
unstub();
eq(overcap, "", "DIFF-010: a genuinely over-cap source still skips (blob)");
ok(exts.indexOf("") >= 0, "DIFF-015: the plain-lexer retry was attempted first");

//  --- 4. an unrelated error still propagates (no new swallowing) ------------
stub(function () { throw "weave.fold: nonsense"; });
throws(run, "DIFF-015: a non-\"full\" error is still rethrown");
unstub();

//  Restored: the control leg passes again after all the stubbing.
ok(run().indexOf("+BETA") >= 0, "weave.fold restored");

io.log("diff/tokfail/tokfail.js OK\n");
