//  WHY-001 test/why/range/check.js — assert a `why:<path>?<a>..<b>` hunk shades ONLY
//  the (a,b] changes incl deletes (O-token model): for c1..c2 the ONE origin commit c2
//  is shaded — its inserted `BETA` and the surfaced removed `beta` each get a hidden
//  `O` = `commit ?<c2hashlet>#<shade>`; `alpha`/`gamma` render PLAIN (no O); `delta`
//  (a c3 token) is absent.  argv[2] = captured `--tlv` bytes.
"use strict";

const pager = require("views/bro/pager.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }
function eq(a, b, m) { if (a !== b) fail(m + ": " + a + " !== " + b); }

const tlvPath = process.argv[2];
const st = io.lstat(tlvPath);
const sz = Number(st.size);
const fd = io.open(tlvPath, "r");
const rb = io.buf(sz + 16);
io.readAll(fd, rb, sz);
io.close(fd);
const tlv = rb.data().slice();

const hunks = pager.hunksFromTlv(tlv);
ok(hunks.length >= 1, "range: at least one hunk");
const h = hunks[0];
const text = h.text, toks = h.toks;

function tagOf(w) { return String.fromCharCode(65 + ((w >>> 27) & 0x1f)); }
function endOf(w) { return w & 0xffffff; }

//  Full visible text (drop U/O spans): the whole tip view, with the removed `beta`
//  surfaced alongside its replacement `BETA`.
let vis = "", prev = 0;
for (let i = 0; i < toks.length; i++) {
  const end = endOf(toks[i]), tag = tagOf(toks[i]);
  if (tag !== "U" && tag !== "O")
    for (let j = prev; j < end; j++) vis += String.fromCharCode(text[j]);
  prev = end;
}
ok(vis.indexOf("beta") >= 0, "range surfaces the DELETED `beta` (deletes stay visible)");
ok(vis.indexOf("BETA") >= 0, "range shows the inserted `BETA`");
ok(vis.indexOf("delta") < 0, "range excludes `delta` (a c3 token, out of (c1,c2])");

//  Washed tokens (immediately followed by an `O`) are ONLY the c2 changes → ONE
//  distinct commit; unchanged base (`alpha`/`gamma`) is NOT washed (stays white).
const shas = {};
let washed = 0;
prev = 0;
for (let i = 0; i < toks.length; i++) {
  const hi = endOf(toks[i]);
  if (i + 1 < toks.length && tagOf(toks[i + 1]) === "O") {
    washed++;
    const spell = utf8.Decode(text.slice(hi, endOf(toks[i + 1])));
    const m = /^commit \?([0-9a-f]{6,40})#([0-9]+)$/.exec(spell);
    ok(!!m, "range O spell is `commit ?<hashlet>#<shade>`: " + spell);
    shas[m[1]] = true;
    const span = utf8.Decode(text.slice(prev, hi));
    ok(span.indexOf("alpha") < 0 && span.indexOf("gamma") < 0,
       "unchanged base (`alpha`/`gamma`) is NOT washed: " + span);
  }
  prev = hi;
}
ok(washed > 0, "range washes the changed tokens");
eq(Object.keys(shas).length, 1, "range shades exactly ONE origin commit (c2)");

io.log("test/why/range OK (one commit shaded, deletes surfaced, base plain)\n");
