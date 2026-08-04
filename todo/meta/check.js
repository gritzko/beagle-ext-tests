//  test/todo/meta/check.js — TODO-004 assert: BOTH halves of a meta pair carry
//  a click spell, minted as the context-less `O` spells BE-054 reserves for a
//  verb click (U stays addresses), so the pager drives them arg-blind and the
//  VERB resolves the arg.  Ruling 2026-08-03: the spell carries the WHOLE ARG
//  LINE with that ONE key's filter replaced — never a `todo(key,value)` call.
//
//  argv[2] = captured `jab todo … --tlv` bytes (a file); argv[3] = mode:
//    page — a rendered ticket page (TODO-011: `ticket TST-001`): the mkd grammar's own `T`
//           token (`Now:`) is followed by an O carrying the whole arg line with
//           `Now:*` in it, and the value token by the same line with
//           `Now:OPEN`.  A page's arg line is the ticket ID, which carries its
//           TOPIC — a page takes no filters, so the id resolves to `TST`.
//    list — `todo TST Now:* Sev:*`: each inline value's O carries the WHOLE
//           line with only ITS key rewritten (the other filter stays put, in
//           place), and the key still carries its page nav — TODO-011:
//           `ticket <KEY>`, since a KEY names a page, not a listing.
//    uri  — `ticket OTH-001`: a value carrying a colon (a `Rev:` branch URI) is
//           not expressible as a filter arg, so that half does NOT click — its
//           key half still offers the `Rev:*` presence filter.
//  In every mode the hidden spell bytes must NOT leak into the visible text.
"use strict";

const pager = require("views/bro/pager.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }

const tlvPath = process.argv[2];
const mode = process.argv[3] || "page";
const st = io.lstat(tlvPath);
const sz = Number(st.size);
const fd = io.open(tlvPath, "r");
const rb = io.buf(sz + 16);
io.readAll(fd, rb, sz);
io.close(fd);
const hunks = pager.hunksFromTlv(rb.data().slice());
ok(hunks.length >= 1, "todo produced at least one hunk");

function tagOf(w) { return String.fromCharCode(65 + ((w >>> 27) & 0x1f)); }
function endOf(w) { return w & 0xffffff; }

//  BE-054: every (visibleTokenText, followingO) pair of a hunk — exactly what
//  the pager's _uriAt reads when a cell of that token is clicked.
function uPairs(text, toks) {
  const out = [];
  let prev = 0;
  for (let i = 0; i < toks.length; i++) {
    const end = endOf(toks[i]);
    if (tagOf(toks[i]) !== "O" && i + 1 < toks.length && tagOf(toks[i + 1]) === "O")
      out.push({ text: utf8.Decode(text.slice(prev, end)),
                 u: utf8.Decode(text.slice(end, endOf(toks[i + 1]))) });
    prev = end;
  }
  return out;
}
function visibleText(text, toks) {
  let out = "", prev = 0;
  for (let i = 0; i < toks.length; i++) {
    const end = endOf(toks[i]);
    if (tagOf(toks[i]) !== "O") out += utf8.Decode(text.slice(prev, end));
    prev = end;
  }
  return out;
}

let pairs = [], visible = "";
for (const h of hunks) {
  const toks = h.toks || new Uint32Array(0);
  pairs = pairs.concat(uPairs(h.text, toks));
  visible += visibleText(h.text, toks);
}
ok(visible.indexOf("todo(") < 0, "a `todo(key,value)` call survived the arg-line rework");
ok(visible.indexOf("todo TST") < 0, "the hidden arg-line spell leaked into the visible text");

//  A click on `text` drives `spell` (the token text is matched trimmed — the
//  mkd value token opens with the pair's separating space).
function drives(text, spell) {
  return pairs.some(function (p) { return p.text.trim() === text && p.u === spell; });
}
//  Does `text` carry ANY click at all?
function clicks(text) {
  return pairs.some(function (p) { return p.text.trim() === text; });
}

if (mode === "page") {
  //  the arg line is `TST-001`, so every spell resolves it to the topic TST.
  ok(drives("Now:", "todo TST Now:*"), "the `Now:` key half drives no presence filter");
  ok(drives("OPEN", "todo TST Now:OPEN"), "the `Now:` value half drives no whole-line filter");
  ok(drives("Sev:", "todo TST Sev:*"), "the `Sev:` key half drives no presence filter");
  ok(drives("HIGH", "todo TST Sev:HIGH"), "the `Sev:` value half drives no whole-line filter");
  ok(drives("Who:", "todo TST Who:*"), "the `Who:` key half drives no presence filter");
  ok(drives("gritzko", "todo TST Who:gritzko"), "the `Who:` value half drives no whole-line filter");
} else if (mode === "list") {
  ok(drives("TST-002", "ticket TST-002"), "a list row lost its `ticket <KEY>` nav spell");
  //  ONE key is rewritten and the REST of the line is left alone, in place.
  ok(drives("OPEN", "todo TST Now:OPEN Sev:*"), "a `Now:` value click does not replace only Now:");
  ok(drives("HIGH", "todo TST Now:* Sev:HIGH"), "a `Sev:` value click does not replace only Sev:");
  ok(drives("CRIT", "todo TST Now:* Sev:CRIT"), "a second row's value click lost the other filter");
  ok(!pairs.some(function (p) { return p.u.indexOf("Now:*") >= 0 && p.u.indexOf("Now:OPEN") >= 0; }),
     "a click APPENDED a second filter for the same key instead of replacing it");
} else if (mode === "indent") {
  //  a PLAINLY INDENTED header block (four spaces) clicks exactly like a
  //  column-0 one — the index and the render read it through ONE matcher.
  ok(drives("Now:", "todo TST Now:*"), "an indented `Now:` key half lost its spell");
  ok(drives("OPEN", "todo TST Now:OPEN"), "an indented `Now:` value half lost its spell");
  ok(drives("Sev:", "todo TST Sev:*"), "an indented `Sev:` key half lost its spell");
  ok(drives("MED", "todo TST Sev:MED"), "an indented `Sev:` value half lost its spell");
} else if (mode === "scope") {
  //  only the block directly under the header is the TICKET's meta: the pair
  //  nested in a WIP bullet and the late column-0 pair are not, so they carry
  //  no filter spell — a click that could not be answered is never minted.
  ok(drives("Now:", "todo TST Now:*"), "the in-scope header pair lost its spell");
  ok(!clicks("Fix:"), "a pair nested in a bullet minted a ticket-meta click");
  ok(!clicks("Msg:"), "a late column-0 pair minted a ticket-meta click");
} else {
  //  `Rev: file:/a/branch/uri` — the value carries a colon, and a colon
  //  SEPARATES, so no filter arg can name it.
  ok(drives("Rev:", "todo OTH Rev:*"), "the `Rev:` key half lost its presence filter");
  ok(!clicks("file:/a/branch/uri"), "a colon-carrying value minted an unusable filter spell");
  //  a SPACED value is still expressible — it rides its despaced index form.
  ok(drives("Ann Example", "todo OTH Who:annexample"),
     "a spaced value does not ride its despaced index form");
}

io.log("test/todo/meta OK (" + mode + ", " + pairs.length + " O pairs)\n");
