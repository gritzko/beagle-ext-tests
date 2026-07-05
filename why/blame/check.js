//  WHY-001 test/why/blame/check.js — assert the `why:<path>` blame hunk under the
//  O (origin) token model: each ORIGIN-attributed token is IMMEDIATELY followed by a
//  hidden `O` token whose bytes are `#rrggbb commit ?<hashlet>` — a LEADING baked bg
//  (the view resolves hue f(sha) + age paleness) then the click spell.  The renderer
//  applies the `#rrggbb`; the pager strips it → `commit ?<hashlet>`.
//  The M distinct origin commits map to M distinct commit hashlets.
//    argv[2] = captured `jab why:<path> --tlv` bytes; argv[3] = expected M.
"use strict";

const pager = require("views/bro/pager.js");
const bro   = require("view/bro.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }
function eq(a, b, m) { if (a !== b) fail(m + ": " + a + " !== " + b); }

const tlvPath = process.argv[2];
const wantM = parseInt(process.argv[3], 10);

const st = io.lstat(tlvPath);
const sz = Number(st.size);
const fd = io.open(tlvPath, "r");
const rb = io.buf(sz + 16);
io.readAll(fd, rb, sz);
io.close(fd);
const tlv = rb.data().slice();

const hunks = pager.hunksFromTlv(tlv);
ok(hunks.length >= 1, "why feeds at least one content hunk");
const h = hunks[0];
const text = h.text, toks = h.toks;
ok(toks.length > 0, "blame hunk carries tok32 spans");

function tagOf(w) { return String.fromCharCode(65 + ((w >>> 27) & 0x1f)); }
function endOf(w) { return w & 0xffffff; }

//  Walk tokens: a WASHED token is one immediately followed by an `O`.  Verify the
//  O spell shape, per-token syntax-tag survival, and that _uriAt resolves each washed
//  token to `commit ?<hashlet>` (the leading `#rrggbb` stripped).  Distinct hashlets.
const shas = {}, syntaxTags = {};
let washed = 0, prev = 0;
for (let i = 0; i < toks.length; i++) {
  const tag = tagOf(toks[i]), hi = endOf(toks[i]);
  if (tag !== "U" && tag !== "O") syntaxTags[tag] = (syntaxTags[tag] || 0) + 1;
  if (i + 1 < toks.length && tagOf(toks[i + 1]) === "O") {
    washed++;
    const spell = utf8.Decode(text.slice(endOf(toks[i]), endOf(toks[i + 1])));
    const m = /^#([0-9a-fA-F]{6}) commit \?([0-9a-f]{6,40})$/.exec(spell);
    ok(!!m, "O spell is `#rrggbb commit ?<hashlet>`: " + spell);
    shas[m[2]] = (shas[m[2]] || 0) + 1;
    //  the pager _uriAt on this token's last visible byte → `commit ?<hashlet>` (no #rgb).
    const click = pager.Pager.prototype._uriAt.call({}, { text: text, toks: toks }, hi - 1);
    eq(click, "commit ?" + m[2], "_uriAt strips #rrggbb → commit ?<hashlet>");
    //  the bg is a truecolor (bm===3) wash, never a fg wash (fm===0).
    const bg = bro.whyBgAt(text, toks, i);
    eq(bg.bm, 3, "washed token bg is a truecolor wash");
    eq(bg.fm, 0, "washed token wash is bg-only");
  }
  prev = hi;
}
ok(washed > 0, "at least one washed (origin) token");
const distinct = Object.keys(shas);
eq(distinct.length, wantM, "M distinct origin commits");
ok(Object.keys(syntaxTags).length >= 2, "per-token syntax tags survive (fg diversity)");

//  RENDER seam: colorWhyHunk (the paintWhyRow path the pager + pipe --color share)
//  carries a syntax fg SGR AND >=2 distinct 48;2;R;G;B truecolor commit-bg washes.
const colored = utf8.Decode(bro.colorWhyHunk("", text, toks, 200));
ok(/\[([0-9]+;)*(3[0-9]|9[0-9]|38;5;[0-9]+)/.test(colored), "render carries a syntax fg SGR");
const pbg = {}; let mm; const re = /48;2;([0-9]+;[0-9]+;[0-9]+)/g;
while ((mm = re.exec(colored))) pbg[mm[1]] = true;
ok(Object.keys(pbg).length >= 2, "render carries >=2 distinct commit-bg washes: " + Object.keys(pbg).length);

io.log("test/why/blame OK (" + wantM + " commits, O targets, age shades, fg+bg render)\n");
