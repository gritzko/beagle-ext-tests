//  test/commit/ticket/check.js — COMMIT-007: `jab commit:?<sha>` must (1) fuse an
//  issue key in the message into an `F` token carrying a hidden `U` ticket-file
//  click-target (the commit-view twin of BRO-012's log: producer splice), and (2)
//  render the author/committer date HUMAN (the lib `ron.date`), not the raw epoch.
//
//  argv[2] = captured `jab commit:?<sha> --tlv` bytes (a file);
//  argv[3] = the ticket code cited in the message (ABC-123).
//  Reparses the TLV via the pager's own hunksFromTlv; asserts the metadata hunk
//  carries an `F` token for the code with an adjacent hidden `U` decoding (via the
//  pager `_uriAt`) to the ticket's `cat:` nav URI, AND that no visible line shows a
//  bare 10-digit epoch.  RED before the fix (no F/U, raw epoch); GREEN after.
"use strict";

const discover = require("core/discover.js");
globalThis.be = Object.assign(globalThis.be || {}, discover);   // be.todoRoot/navCwd/find
const pager = require("views/bro/pager.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }
function eq(a, b, m) { if (a !== b) fail(m + ": " + JSON.stringify(a) + " !== " + JSON.stringify(b)); }

const TLV = process.argv[2];
const CODE = process.argv[3];

//  Read the captured --tlv stream and reparse it through the pager's own reader.
const st = io.lstat(TLV);
const sz = Number(st.size);
const fd = io.open(TLV, "r");
const rb = io.buf(sz + 16);
io.readAll(fd, rb, sz);
io.close(fd);
const hunks = pager.hunksFromTlv(rb.data().slice());
ok(hunks.length >= 1, "commit view feeds the metadata hunk first");

function tagOf(w) { return String.fromCharCode(65 + ((w >>> 27) & 0x1f)); }
function endOf(w) { return w & 0xffffff; }

const h = hunks[0];
const text = h.text, toks = h.toks;
ok(toks.length > 0, "color/tlv metadata hunk carries tok32 spans");

//  ---- (1) the message issue key is an `F` token with a hidden `U` ticket URI ---
let fIdx = -1, fLo = 0, prev = 0;
for (let i = 0; i < toks.length; i++) {
  const end = endOf(toks[i]);
  if (tagOf(toks[i]) === "F" && utf8.Decode(text.slice(prev, end)) === CODE) { fIdx = i; fLo = prev; }
  prev = end;
}
ok(fIdx >= 0, "the message fuses " + CODE + " into an F token");
const uTag = tagOf(toks[fIdx + 1]);
eq(uTag, "U", "a hidden U ticket URI is spliced right after the message F token");

//  The hidden U bytes ARE the ticket's cat: nav URI; a pager click on the F cell
//  (the _uriAt consumer path) resolves to the SAME URI.
const uLo = endOf(toks[fIdx]);
const uHi = endOf(toks[fIdx + 1]);
const uri = utf8.Decode(text.slice(uLo, uHi));
ok(uri.indexOf("cat:") === 0, "ticket U-target is a cat: nav URI: " + uri);
ok(uri.indexOf(CODE + ".") >= 0, "ticket U-target names the ticket file (" + CODE + ".<ext>): " + uri);
ok(uri.indexOf("todo/ABC/") >= 0, "ticket U-target carries the todo/<TOPIC>/ nesting: " + uri);
const click = pager.Pager.prototype._uriAt.call({}, { text: text, toks: toks }, uLo - 1);
eq(click, uri, "_uriAt on the F cell opens the ticket URI");

//  ---- (2) the author/committer date is HUMAN, not the raw epoch ---------------
//  Drop every U-tagged span → the VISIBLE metadata text; no line may end in a
//  bare `<10-digit-epoch> <tz>` (the raw git author time COMMIT-007 replaces).
let vis = "", vprev = 0;
for (let i = 0; i < toks.length; i++) {
  const end = endOf(toks[i]);
  if (tagOf(toks[i]) !== "U")
    for (let j = vprev; j < end; j++) vis += String.fromCharCode(text[j]);
  vprev = end;
}
ok(/\nauthor /.test(vis), "visible author header survives");
ok(/\ncommitter /.test(vis), "visible committer header survives");
ok(!/^(author|committer) .*\d{10} [+-]\d{4}\s*$/m.test(vis),
   "no author/committer line shows a bare 10-digit epoch (human date rendered)");
//  The ident `Name <email>` must remain (only the epoch/tz tail is replaced).
ok(/^author .*<[^>]+>/m.test(vis), "the author ident Name <email> is preserved");

io.log("test/commit/ticket OK (message F + hidden U ticket URI, human date)\n");
