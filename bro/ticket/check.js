//  test/bro/ticket/check.js — BRO-012: an `F` issue-key token opens its ticket
//  file, and a ticket code in a `log:` commit summary is clickable too.  Both
//  paths converge on shared/ticket.js's resolver, which owns the ROOT ORDER via
//  be.todoRoot(): $TODO_ROOT env > current wt root (be.repo) > open/launch wt
//  root (io.cwd()).  key → todo/<TOPIC>/<KEY>.ext under the first hit → a cat:
//  nav URI whose `//name` names the winning root.
//
//  RED before the fix: a body `F` token has no adjacent `U`, so the pager
//  `_uriAt` returned null (a dead link); a log summary code was one flat `S`
//  span (no `F`, no `U`), so a click on it returned null.  ALSO RED if the
//  resolver ignores be.todoRoot()'s order.  GREEN after.
//
//  argv[2] = SRC_ROOT dir (holds sibling trees envtree/curtree/opentree);
//  argv[3] = a captured `jab log: --tlv` whose newest summary carries the code;
//  argv[4] = the ticket code (ABC-123);  argv[5] = the scenario tag (env|
//  current|open);  argv[6] = the tree name the resolver MUST pick this run.
"use strict";

const discover = require("core/discover.js");
globalThis.be = Object.assign(globalThis.be || {}, discover);   // be.todoRoot/navCwd/find
const pager = require("views/bro/pager.js");
const ticket = require("shared/ticket.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }
function eq(a, b, m) { if (a !== b) fail(m + ": " + JSON.stringify(a) + " !== " + JSON.stringify(b)); }

const SRC = process.argv[2];                      // SRC_ROOT (sibling trees)
const TLV = process.argv[3];                      // captured jab log: --tlv path
const CODE = process.argv[4];                     // the ticket code in the summary
const SCEN = process.argv[5];                     // env | current | open
const WANT = process.argv[6];                     // the tree name the resolver picks
const WANT_AUTH = "//" + WANT;                    // its `//name` nav authority

//  Simulate the CURRENT wt (the nav'd view's authority) as curtree; the OPEN /
//  launch wt is io.cwd() (opentree, where jab launched).  be.todoRoot() reads
//  be.repo for the current root; $TODO_ROOT (env) is set by run.sh per scenario.
be.repo = { wt: SRC + "/curtree" };

//  ---- (0) the resolver honours the ROOT ORDER (env > current > open) --------
const resolved = ticket.ticketUri(CODE);
ok(resolved, "ticketUri(" + CODE + ") resolves in the " + SCEN + " scenario");
ok(resolved.indexOf("cat:") === 0, "ticket URI is a cat: nav URI: " + resolved);
ok(resolved.indexOf(CODE + ".") >= 0, "ticket URI names the ticket file: " + resolved);
ok(resolved.indexOf("todo/") >= 0, "ticket URI carries the todo/<TOPIC>/ nesting: " + resolved);
ok(resolved.indexOf(WANT_AUTH + "/") >= 0,
   SCEN + " root must win: URI " + resolved + " should carry " + WANT_AUTH);
eq(ticket.ticketUri("ZZZ-999"), null, "a missing ticket resolves to null (quiet no-op)");

//  ---- (a) a body `F` issue-key token opens its ticket ------------------------
//  A real `.mkd` body tokenized by the SAME grammar that mints the body `F` —
//  `CODE` fuses into ONE `F` token with NO adjacent `U`.
const body = utf8.Encode("see " + CODE + " for details\n");
const btoks = tok.parse(body, "mkd");
//  Sanity: the code IS an `F` token (not split), and there is NO `U` anywhere.
let fSpan = null, hasU = false, prev = 0;
for (let i = 0; i < btoks.length; i++) {
  const end = btoks[i] & 0xffffff;
  const tag = String.fromCharCode(65 + ((btoks[i] >>> 27) & 0x1f));
  if (tag === "F" && utf8.Decode(body.slice(prev, end)) === CODE) fSpan = { lo: prev, hi: end };
  if (tag === "U") hasU = true;
  prev = end;
}
ok(fSpan, "the body tokenizes " + CODE + " into one F token");
ok(!hasU, "the body carries NO U token (the gap: an F issue key has none)");

const hunk = { uri: WANT_AUTH + "/todo/DOC/DOC-1.mkd", verb: "hunk", text: body, toks: btoks, kind: "file" };
const p = new pager.Pager(-1, { color: false });
//  A click anywhere on the `F` token derives the ticket URI (the resolver owns
//  the root order — the pager passes NO authority now).
for (let off = fSpan.lo; off < fSpan.hi; off++) {
  const got = p._uriAt(hunk, off);
  eq(got, resolved, "body F-token click at off " + off + " opens the ticket (" + SCEN + ")");
}
//  A click OFF the code (plain S text) is NOT a ticket link (no false positive).
eq(p._uriAt(hunk, 0), null, "a click on plain text is not a ticket link");

//  ---- (b) a `log:` commit summary code is clickable --------------------------
//  Load the captured `jab log: --tlv` and assert the newest row's summary now
//  carries an `F` token for CODE followed by a hidden `U` ticket URI, so the
//  existing `_uriAt` opens it with NO further pager change.
const st = io.lstat(TLV);
const sz = Number(st.size);
const fd = io.open(TLV, "r");
const rb = io.buf(sz + 16);
io.readAll(fd, rb, sz);
io.close(fd);
const hunks = pager.hunksFromTlv(rb.data().slice());
ok(hunks.length >= 1, "log produced at least one hunk");
const lh = hunks[0];

//  Find the CODE's `F` token in the log body; the NEXT token must be a `U`
//  whose hidden bytes are the ticket URI.  Then a click on the code opens it.
const ltext = lh.text, ltoks = lh.toks;
let codeOff = -1, fIdx = -1, lprev = 0;
for (let i = 0; i < ltoks.length; i++) {
  const end = ltoks[i] & 0xffffff;
  const tag = String.fromCharCode(65 + ((ltoks[i] >>> 27) & 0x1f));
  if (tag === "F" && utf8.Decode(ltext.slice(lprev, end)) === CODE) { codeOff = lprev; fIdx = i; }
  lprev = end;
}
ok(fIdx >= 0, "the log summary fuses " + CODE + " into an F token");
const nTag = String.fromCharCode(65 + ((ltoks[fIdx + 1] >>> 27) & 0x1f));
eq(nTag, "U", "a hidden U ticket URI is spliced right after the summary F token");

//  Drive the pager click path on the code cell → it opens the ticket URI.
const pl = new pager.Pager(-1, { color: false, driveSpell: function () { return []; } });
pl.setHunks(hunks);
const clickUri = pl._uriAt(lh, codeOff);
ok(clickUri && clickUri.indexOf("cat:") === 0, "log summary code click opens a cat: ticket URI: " + clickUri);
ok(clickUri.indexOf(CODE + ".") >= 0, "log click opens the code's ticket file: " + clickUri);

//  ---- (c) a cat: file view links an F issue-key to its TICKET, not grep ------
//  The REPORTED bug: views/cat `withLinks` blankets every grepable word with a
//  `grep:#<word>` U, INCLUDING the issue key, so `_uriAt`'s adjacent-U check
//  opened grep before the ticket fallback.  Drive the real `cat: --tlv` and
//  assert the F token's adjacent U is the TICKET URI, not a grep spell.
const CATTLV = process.argv[7];
if (CATTLV) {
  const cs = io.lstat(CATTLV);
  const cfd = io.open(CATTLV, "r");
  const cbuf = io.buf(Number(cs.size) + 16);
  io.readAll(cfd, cbuf, Number(cs.size));
  io.close(cfd);
  const chunks = pager.hunksFromTlv(cbuf.data().slice());
  ok(chunks.length >= 1, "cat: produced at least one hunk");
  const ch = chunks[0];
  let cOff = -1, cIdx = -1, cprev = 0;
  for (let i = 0; i < ch.toks.length; i++) {
    const end = ch.toks[i] & 0xffffff;
    const tag = String.fromCharCode(65 + ((ch.toks[i] >>> 27) & 0x1f));
    if (tag === "F" && utf8.Decode(ch.text.slice(cprev, end)) === CODE) { cOff = cprev; cIdx = i; }
    cprev = end;
  }
  ok(cIdx >= 0, "cat: fuses " + CODE + " into an F token");
  const uTag = String.fromCharCode(65 + ((ch.toks[cIdx + 1] >>> 27) & 0x1f));
  eq(uTag, "U", "cat: the F token is followed by a U click-target");
  const uStr = utf8.Decode(ch.text.slice(ch.toks[cIdx] & 0xffffff, ch.toks[cIdx + 1] & 0xffffff));
  ok(uStr.indexOf("cat:") === 0 && uStr.indexOf("todo/") >= 0,
     "cat: F links to the TICKET file, not the word: " + uStr);
  ok(uStr.indexOf("grep") < 0, "cat: F U-target is NOT a grep spell: " + uStr);
  const pc = new pager.Pager(-1, { color: false, driveSpell: function () { return []; } });
  pc.setHunks(chunks);
  const catClick = pc._uriAt(ch, cOff);
  ok(catClick && catClick.indexOf("todo/") >= 0 && catClick.indexOf("grep") < 0,
     "cat: click on the code opens the ticket, not grep: " + catClick);
}

//  ---- BRO-012: a ticket click from a ?ref-scoped view DROPS the ref ---------
//  The reported diff-view bug: the ticket URI (`cat://journal/…`) inherited the
//  diff's `?hash` (URI-012 context inheritance) → that hash is meaningless in
//  the journal repo → "no hunks".  Fix: inherit ?ref ONLY for a relative click;
//  an own-//authority (cross-repo) ticket link keeps its own (absent) ref.
const pr = new pager.Pager(-1, { color: false, driveSpell: function () { return []; } });
pr._verbUri = function () { return { uri: "diff://coderepo?deadbeef" }; };
const tspell = pr._resolveSpell("cat://journal/todo/URI/URI-014.mkd");
ok(tspell.indexOf("?") < 0, "a ticket click from a ?ref view DROPS the ref: " + tspell);
ok(tspell.indexOf("deadbeef") < 0, "the cross-repo context hash does NOT ride the ticket link: " + tspell);
ok(tspell.indexOf("todo/URI/URI-014.mkd") >= 0, "the ticket path survives: " + tspell);
const rel = pr._resolveSpell("diff:src/x.c");
ok(rel.indexOf("deadbeef") >= 0, "a RELATIVE click still inherits the context ?ref (URI-012 intact): " + rel);

io.log("test/bro/ticket OK (" + SCEN + ": body F + log summary + resolver order + no-op)\n");
