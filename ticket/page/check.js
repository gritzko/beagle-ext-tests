//  test/ticket/page/check.js — TODO-011 assert: the SPELL SWEEP of a rendered
//  ticket page.  The split moved the page out of `todo` into its own `ticket`
//  view, and the ONE thing that was allowed to change with it is the verb name
//  on the click spells that land on a PAGE.  So every spell class is pinned:
//
//    a bare ticket key in the body (`F` token)   -> `ticket <KEY>`
//    a `[KEY]` reflink run (`G` … `G`)           -> `ticket <KEY>`
//    a ticket-VALUED meta pair's value (TODO-008)-> `ticket <KEY>`
//    a meta pair's KEY half                      -> `todo <TOPIC> Key:*`
//    a meta pair's non-ticket VALUE half         -> `todo <TOPIC> Key:value`
//    a non-ticket in-tree reflink target         -> `cat <meta-root-rel>`
//    the page's OWN key                          -> NO spell (no self-link)
//
//  The filter halves stay `todo` spells BY DESIGN: a filter narrows a LISTING
//  and listings are the board's business (the page's arg line is its ticket id,
//  which carries its TOPIC — argLineWith).  That cross-view landing is the
//  point of the split, not an oversight.
//
//  argv[2] = captured `jab ticket <KEY> --tlv` bytes (a file); argv[3] = the key.
//  Hidden spell bytes must never leak into the visible text.
"use strict";

const pager = require("views/bro/pager.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }

const tlvPath = process.argv[2];
const key = process.argv[3] || "";
const st = io.lstat(tlvPath);
const sz = Number(st.size);
const fd = io.open(tlvPath, "r");
const rb = io.buf(sz + 16);
io.readAll(fd, rb, sz);
io.close(fd);
const hunks = pager.hunksFromTlv(rb.data().slice());
ok(hunks.length >= 1, "ticket " + key + " produced at least one hunk");

function tagOf(w) { return String.fromCharCode(65 + ((w >>> 27) & 0x1f)); }
function endOf(w) { return w & 0xffffff; }

//  BE-054: all (visibleTokenText, followingO) pairs — every token whose NEXT
//  token is an `O` yields { text, u } with the O's hidden spell bytes.
const pairs = [];
let visible = "";
for (const h of hunks) {
  const toks = h.toks || new Uint32Array(0);
  let prev = 0;
  for (let i = 0; i < toks.length; i++) {
    const end = endOf(toks[i]);
    const text = utf8.Decode(h.text.slice(prev, end));
    if (tagOf(toks[i]) !== "O") {
      visible += text;
      if (i + 1 < toks.length && tagOf(toks[i + 1]) === "O")
        pairs.push({ text: text, u: utf8.Decode(h.text.slice(end, endOf(toks[i + 1]))) });
    }
    prev = end;
  }
}
ok(visible.indexOf("ticket PAG-") < 0, "a hidden `ticket <KEY>` spell leaked into the visible text");
ok(visible.indexOf("todo PAG ") < 0, "a hidden `todo <TOPIC> …` spell leaked into the visible text");

//  every spell a visible word drives (a reflink run gives each of its tokens
//  the same spell, so `[`/label/`]` all answer).
function drives(word, spell) {
  return pairs.some(function (p) { return p.text.trim() === word && p.u === spell; });
}
function spellsOf(word) {
  return pairs.filter(function (p) { return p.text.trim() === word; })
              .map(function (p) { return p.u; });
}

//  --- the KEY landings: every one of them is a `ticket` spell ---------------
if (key === "PAG-001") {
  ok(drives("PAG-002", "ticket PAG-002"), "the bare body key PAG-002 lost its `ticket` nav");
  ok(drives("PAG-003", "ticket PAG-003"), "the `[PAG-003]` reflink lost its `ticket` nav");
  ok(drives("[", "ticket PAG-003"), "the reflink's opening `[` carries no spell");
  //  TODO-008: a ticket-shaped meta VALUE jumps — registered `See:` and the
  //  UNREGISTERED `Zzz:` alike (the VALUE's lexical class alone decides).
  ok(drives("PAG-002", "ticket PAG-002"), "the `See:` value lost its jump");
  ok(drives("PAG-003", "ticket PAG-003"), "the `Zzz:` value lost its jump");
  //  --- the FILTER halves: table business, still `todo` spells --------------
  ok(drives("Now:", "todo PAG Now:*"), "the `Now:` key half is not the presence filter");
  ok(drives("OPEN", "todo PAG Now:OPEN"), "the `Now:` value half is not the whole-line filter");
  ok(drives("Sev:", "todo PAG Sev:*"), "the `Sev:` key half is not the presence filter");
  ok(drives("MED", "todo PAG Sev:MED"), "the `Sev:` value half is not the whole-line filter");
  ok(drives("See:", "todo PAG See:*"), "the `See:` KEY half stopped filtering");
  ok(drives("Zzz:", "todo PAG Zzz:*"), "the `Zzz:` KEY half stopped filtering");
  //  --- a non-ticket in-tree page stays a `cat` spell -----------------------
  ok(drives("W", "cat wiki/Sample.mkd"), "the `[W]` refdef reflink lost its `cat` spell");
  ok(drives("Sample", "cat wiki/Sample.mkd"), "the `/wiki/Sample` shortcut lost its `cat` spell");
} else {
  //  the FAT page (todo/PAG/PAG-002/README.mkd): one dir deeper, same answers.
  ok(drives("PAG-001", "ticket PAG-001"), "the fat page's bare body key lost its `ticket` nav");
  ok(drives("PAG-003", "ticket PAG-003"), "the fat page's `[PAG-003]` reflink lost its nav");
  ok(drives("PAG-001", "ticket PAG-001"), "the fat page's `Sub:` value lost its jump");
  ok(drives("Now:", "todo PAG Now:*"), "the fat page's `Now:` key half stopped filtering");
  ok(drives("HIGH", "todo PAG Sev:HIGH"), "the fat page's `Sev:` value half stopped filtering");
  //  a value carrying a colon (a `Rev:` URI) is not expressible as a filter
  //  arg, so that half does NOT click — only its key's presence form remains.
  ok(drives("Rev:", "todo PAG Rev:*"), "the `Rev:` key half lost its presence filter");
  ok(spellsOf("http://example.org/x").length === 0,
     "a colon-carrying `Rev:` value must not click");
  ok(drives("W", "cat wiki/Sample.mkd"), "the fat page's `[W]` reflink lost its `cat` spell");
  ok(drives("Sample", "cat wiki/Sample.mkd"), "the fat page's shortcut lost its `cat` spell");
}

//  --- the page's OWN key never self-links ------------------------------------
for (const u of spellsOf(key))
  ok(u !== "ticket " + key, "the page's own key " + key + " minted a self-link");
//  ...and NOTHING on a page spells the retired `todo <KEY>` form any more.
for (const p of pairs)
  ok(!/^todo [A-Z]+-[0-9]+$/.test(p.u),
     "a retired `todo <KEY>` page spell survived on '" + p.text.trim() + "'");

io.log("test/ticket/page OK (" + key + ", " + pairs.length + " spell pairs)\n");
