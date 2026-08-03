//  test/done/buttons/check.js — BE-040 r3 assert: the `[done]` button pair on
//  `todo` list rows, over a captured `jab todo … --tlv` stream.
//
//  argv: <tlv-file> KEY… -- ABSENTKEY…   Each KEY (an OPEN listed ticket) must
//  sit on ONE row shaped  F:KEY  O:"todo KEY"  …  Y:"[done]"  O:"done KEY"  …\n
//  (BE-054: the nav is now a context-less O click spell, U reserved for real
//  addresses; the BE-041 house scheme: nav FIRST so a title click still navigates, the
//  hidden O spell RAW `done KEY`, nothing else).  Each ABSENTKEY (closed /
//  other-topic) must have NO row and NO `done` spell anywhere.  The raw spell
//  bytes must never leak into the VISIBLE text; the `[done]` label must.
"use strict";

const pager = require("views/bro/pager.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }

const tlvPath = process.argv[2];
const want = [], absent = [];
let sep = false;
for (let i = 3; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a === "--") { sep = true; continue; }
  (sep ? absent : want).push(a);
}

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

//  Flatten every hunk into an ordered token list [{ tag, text }].
const toks = [];
let visible = "";
for (const h of hunks) {
  let prev = 0;
  const tk = h.toks || new Uint32Array(0);
  for (let i = 0; i < tk.length; i++) {
    const end = endOf(tk[i]);
    const text = utf8.Decode(h.text.slice(prev, end));
    toks.push({ tag: tagOf(tk[i]), text: text });
    if (tagOf(tk[i]) !== "U" && tagOf(tk[i]) !== "O") visible += text;
    prev = end;
  }
}

//  ONE row: from the F:KEY token to the next visible "\n"-ending S token.
function assertRow(key) {
  let i = toks.findIndex(function (t) { return t.tag === "F" && t.text === key; });
  ok(i >= 0, "no F token for OPEN row " + key);
  ok(toks[i + 1] && toks[i + 1].tag === "O" && toks[i + 1].text === "todo " + key,
     key + ": the hidden O `todo " + key + "` nav must directly follow the key");
  //  TODO-005: the single `[done]` Y label became a two-button PANEL — the ` ✔`
  //  (heavy check) and ` ✗` faces, each on its own class tag with its own hidden O.  A button
  //  face is followed DIRECTLY by its spell, and the spell now opens with the
  //  button's `#<pale><tone> ` colour prefix (the pager sheds it before driving).
  function panelFace(face, verb) {
    let saw = -1;
    for (let j = i + 2; j < toks.length; j++) {
      const t = toks[j];
      if (t.tag !== "U" && t.tag !== "O" && t.text === face) { saw = j; break; }
      if (t.tag !== "U" && t.tag !== "O" && t.text.indexOf("\n") >= 0)
        fail(key + ": row ended before the `" + face + "` panel face");
    }
    ok(saw >= 0, key + ": no visible `" + face + "` panel face on the row");
    const o = toks[saw + 1];
    const want = verb + " " + key;
    ok(o && o.tag === "O" && o.text.slice(-want.length) === want,
       key + ": `" + face + "` must be followed by the hidden O `" + want
         + "` (got " + (o ? o.tag + ":" + JSON.stringify(o.text) : "nothing") + ")");
  }
  panelFace(" ✔", "done");
  panelFace(" ✗", "dont");
}

for (const k of want) assertRow(k);
for (const k of absent) {
  ok(!toks.some(function (t) { return t.tag === "O" && t.text.slice(-("done " + k).length) === "done " + k; }),
     k + ": a `done " + k + "` O spell exists for a row that must not list");
  ok(visible.indexOf(k) < 0, k + ": a closed/foreign key leaked into the list");
}
ok(visible.indexOf("done " + (want[0] || "")) < 0, "the raw O spell leaked into visible text");
ok(want.length === 0 || visible.indexOf("[ ✔  ✗]") >= 0, "no visible done/dont panel at all");

io.log("test/done/buttons OK (" + want.length + " buttoned, " + absent.length + " absent)\n");
