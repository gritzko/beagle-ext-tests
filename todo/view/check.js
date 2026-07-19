//  test/todo/view/check.js — BE-038 assert: the `todo` view's click targets.
//
//  argv[2] = captured `jab todo … --tlv` bytes (a file); argv[3] = mode:
//    board — every list row whose line starts with a ticket key must carry a
//            hidden `O` token right after the key whose bytes are the CONTEXT-
//            LESS click spell `todo <KEY>` (BE-054: verb clicks are O spells,
//            U is reserved for real addresses); topic header rows link
//            `todo <TOPIC>`.
//    page  — a rendered ticket page: every RESOLVABLE ticket key (fixture:
//            GET-002 inside GET-001's body) is followed by an `O` → `todo
//            GET-002`.  Visible text must not leak the hidden O bytes.
"use strict";

const pager = require("views/bro/pager.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }

const tlvPath = process.argv[2];
const mode = process.argv[3] || "board";
const st = io.lstat(tlvPath);
const sz = Number(st.size);
const fd = io.open(tlvPath, "r");
const rb = io.buf(sz + 16);
io.readAll(fd, rb, sz);
io.close(fd);
const tlv = rb.data().slice();

const hunks = pager.hunksFromTlv(tlv);
ok(hunks.length >= 1, "todo produced at least one hunk");

function tagOf(w) { return String.fromCharCode(65 + ((w >>> 27) & 0x1f)); }
function endOf(w) { return w & 0xffffff; }

//  BE-054: all (visibleTokenText, followingO) pairs of a hunk — every token
//  whose NEXT token is an `O` yields { text, u } with the O's hidden bytes.
function uPairs(text, toks) {
  const out = [];
  let prev = 0;
  for (let i = 0; i < toks.length; i++) {
    const end = endOf(toks[i]);
    if (tagOf(toks[i]) !== "O" && i + 1 < toks.length && tagOf(toks[i + 1]) === "O") {
      const uhi = endOf(toks[i + 1]);
      out.push({ text: utf8.Decode(text.slice(prev, end)),
                 u: utf8.Decode(text.slice(end, uhi)) });
    }
    prev = end;
  }
  return out;
}

//  Visible text (O spans dropped) — the hidden click-spell bytes never leak.
function visibleText(text, toks) {
  let out = "", prev = 0;
  for (let i = 0; i < toks.length; i++) {
    const end = endOf(toks[i]);
    if (tagOf(toks[i]) !== "O") out += utf8.Decode(text.slice(prev, end));
    prev = end;
  }
  return out;
}

let pairs = [];
let visible = "";
for (const h of hunks) {
  const toks = h.toks || new Uint32Array(0);
  pairs = pairs.concat(uPairs(h.text, toks));
  visible += visibleText(h.text, toks);
}
ok(visible.indexOf("todo GET-") < 0, "hidden `todo <KEY>` spell leaked into visible text");

function hasPair(key, spell) {
  //  In a rendered page a reflink key shows as `[KEY]` (one G token); a list
  //  row or bare mention is the plain `KEY` — both must carry the same spell.
  return pairs.some(function (p) {
    return (p.text === key || p.text === "[" + key + "]") && p.u === spell;
  });
}

if (mode === "board") {
  ok(hasPair("GET-001", "todo GET-001"), "board row GET-001 lacks O `todo GET-001`");
  ok(hasPair("GET-002", "todo GET-002"), "board row GET-002 lacks O `todo GET-002`");
  ok(hasPair("PUT-001", "todo PUT-001"), "board row PUT-001 lacks O `todo PUT-001`");
  ok(hasPair("GET", "todo GET") || hasPair("PUT", "todo PUT"),
     "board topic header lacks O `todo <TOPIC>`");
} else {
  ok(hasPair("GET-002", "todo GET-002"), "page key GET-002 lacks O `todo GET-002`");
  //  BE-038 r2 / BE-054: a wiki reflink `[W]` → its refdef target as a meta-
  //  root-relative context-less `cat` O spell (context tree = the meta root).
  ok(hasPair("W", "cat wiki/Sample.mkd"), "page reflink [W] lacks O `cat wiki/Sample.mkd`");
}

io.log("test/todo/view OK (" + mode + ", " + pairs.length + " U pairs)\n");
