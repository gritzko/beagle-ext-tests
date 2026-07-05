//  test/diff/links/links.js — BRO-006 repro: be/views/diff/diff.js must emit a
//  `U` click-target per diff hunk so a pager left-click opens the file at the
//  line (the producer half of BRO-005 mouse nav; mirrors C graf/GRAF.c:522/535).
//
//  A diff hunk's own `.uri` (`diff:<path>?<navver>#L<n>`) IS the nav target.
//  diff.js's `withUTarget(uri, text, toks)` appends those URI bytes to the hunk
//  TEXT and a single `U` token (tag 20) covering them — invisible in plain/color
//  (HUNK.c skips 'U' spans), readable by the pager's _uriAt.  Asserts:
//    RED  (pre-fix): no `withUTarget` export / no `U` token in the hunk toks.
//    GREEN (post-fix): the augmented toks end in a `U` token decoding to the
//                      hunk URI, AND the augmented record's `.plain` render is
//                      byte-identical to the un-augmented one (U bytes hidden).

"use strict";

const { eq, ok, bytesEq } = require("../../lib/assert.js");
const diff = require("views/diff/diff.js");
//  URI-014: the click-target is finalised in diffOut.feed via navRelink (the C
//  `diff:` uri re-baked to the word spell `diff <uri>`) BEFORE withUTarget runs.
const navlib = require("shared/nav.js");

//  --- build ONE real diff hunk via the weave bindings (the diffFile path) ----
//  base `f.c` -> edited `f.c`: a single changed middle line, so emitDiff yields
//  one windowed hunk with the `diff:f.c?<navver>#L1` uri the view navigates to.
const FROM = utf8.Encode("alpha\nbeta\ngamma\n");
const TO   = utf8.Encode("alpha\nBETA\ngamma\n");
const NAVVER = "0000aaaa..0000bbbb";

const wA = abc.ram("WEAVE", 1 << 18);
const wB = abc.ram("WEAVE", 1 << 18);
wA.fold(null, FROM, "c", "0000000000000001");
wB.fold(wA, TO, "c", "0000000000000002");
const fromScope = wB.scope(["0000000000000001"]);
const toScope = wB.scope(["0000000000000001", "0000000000000002"]);

const hd = abc.ram("HUNK", 1 << 18);
wB.emitDiff(fromScope, toScope, "f.c", NAVVER, hd);

//  Grab the (single) hunk record's uri / text / toks + its baseline plain.
hd.rewind();
ok(hd.next(), "fixture: emitDiff yielded a hunk record");
const uri = utf8.Decode(hd.uri);
const text = hd.text.slice();
const toks = hd.toks.slice();
const baseO = io.buf(1 << 16);
hd.plain(baseO);
const basePlain = baseO.data().slice();

ok(uri.indexOf("diff:f.c") === 0, "fixture: hunk uri is diff:f.c…  (got " + uri + ")");
ok(uri.indexOf("#L") > 0, "fixture: hunk uri carries a #L<n> line anchor");

//  --- THE REPRO: diff.js exposes withUTarget and appends a `U` click-target ---
ok(typeof diff.withUTarget === "function",
   "BRO-006: diff.js exports withUTarget (the U click-target builder)");
eq(diff.TAG_U, 20, "BRO-006: TAG_U is 'U'-'A' = 20");

//  URI-014: diffOut.feed re-bakes the C `diff:f.c` uri to the word spell
//  `diff f.c…` (verb OUT of the scheme) BEFORE appending the U-target.
const link = navlib.navRelink(uri);
eq(link, "diff " + uri.slice("diff:".length),
   "URI-014: navRelink turns diff:f.c… into the word spell `diff f.c…`");
ok(link.indexOf("diff //") !== 0, "URI-014: no-authority link is scheme-less `diff f.c…`");

const aug = diff.withUTarget(link, text, toks);

//  The augmented toks are the original side toks PLUS exactly one trailing tok.
eq(aug.toks.length, toks.length + 1, "BRO-006: exactly one extra token appended");
const last = aug.toks[aug.toks.length - 1];
const lastTag = (last >>> 27) & 0x1f;
eq(lastTag, 20, "BRO-006: the appended token is tag 'U' (20)");

//  The U token's hidden bytes [prevEnd .. end) ARE the nav URI — the SAME read
//  the pager's _uriAt does.  end == full text length; prevEnd == visible len.
const prevEnd = aug.toks[aug.toks.length - 2] & 0xffffff;
const uEnd = last & 0xffffff;
eq(uEnd, aug.text.length, "BRO-006: U token end == augmented text length");
eq(prevEnd, text.length, "BRO-006: U bytes start right after the visible text");
const target = utf8.Decode(aug.text.slice(prevEnd, uEnd));
eq(target, link, "URI-014: the U click-target decodes to the word spell `diff f.c…`");

//  --- plain output unchanged: the U bytes are HIDDEN in the render ----------
//  Re-feed the augmented record and render `.plain`; it MUST byte-match the
//  un-augmented baseline (HUNK.c skips 'U' spans), so the diff text is intact.
//  URI-014: the RECORD uri stays C `diff:` scheme form (HUNK.c hunk_uri_is_diff
//  gates the unified render on it) — plain/color UNAFFECTED; only U-target moved.
const sink = abc.ram("HUNK", 1 << 18);
sink.feed(uri, aug.text, aug.toks, "", 0n);
sink.rewind();
ok(sink.next(), "augmented record re-reads");
const augO = io.buf(1 << 16);
sink.plain(augO);
bytesEq(augO.data(), basePlain, "BRO-006: plain render is byte-identical (U hidden)");

//  An empty-uri (text-only gitlink) hunk gets NO target — nothing to navigate.
const none = diff.withUTarget("", text, toks);
eq(none.toks.length, toks.length, "BRO-006: empty-uri hunk gets no U token");

io.log("diff/links/links.js OK\n");
