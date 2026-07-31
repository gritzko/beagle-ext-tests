//  test/bro/elastic/elastic.js — BRO-036 elastic `B` fields, over the REAL
//  producer stream (`jab todo ELS --tlv`) + the REAL Pager on a pty slave.
//  argv[2]=views/bro/pager.js  argv[3]=view/bro.js  argv[4]=views/work/work.js
//  argv[5]=captured tlv.  Checks: (1) the todo title span carries tok tag `B`
//  and work's wt-row subject does too; (2) a no-wrap render at 40 cols keeps
//  `[done]` visible with a `…` cut on the long row and pads the short row so
//  `[done]` ends flush right at cols; (3) soft-wrap ignores `B` (verbatim);
//  (4) a REAL click (_screenToByte/_uriAt) on the flush-right `[done]` lands.
"use strict";
const pager = require(process.argv[2]);
const bro = require(process.argv[3]);
const work = require(process.argv[4]);

function w1(s) { const b = utf8.Encode(s); const x = io.buf(b.length + 8); x.feed(b); io.writeAll(1, x); }
function check(name, cond) { w1((cond ? "ok   " : "FAIL ") + name + "\n"); }

const COLS = 40, ROWS = 10;
function TAG(t) { return String.fromCharCode(65 + ((t >>> 27) & 0x1f)); }
function END(t) { return t & 0xffffff; }
function width(s) { return Array.from(s).length; }

//  --- the captured REAL `todo ELS --tlv` hunk -------------------------------
const fd = io.open(process.argv[5], "r");
const frb = io.buf(1 << 20);
io.read(fd, frb); io.close(fd);
const hunks = pager.hunksFromTlv(frb.data().slice());
check("tlv-hunks", hunks.length >= 1);
const h = hunks[0];
const bodyTxt = utf8.Decode(h.text);
check("tlv-both-rows", bodyTxt.indexOf("ELS-1") >= 0 && bodyTxt.indexOf("ELS-2") >= 0);

//  --- 1. the PRODUCERS tag the field `B` (RED pre-fix: no B tok at all) -----
function bTexts(body, toks) {
  const out = [];
  for (let i = 0; i < toks.length; i++)
    if (TAG(toks[i]) === "B")
      out.push(utf8.Decode(body.subarray(i > 0 ? END(toks[i - 1]) : 0, END(toks[i]))));
  return out;
}
const bs = bTexts(h.text, h.toks);
check("todo-title-tagged-B", bs.length >= 2);
check("todo-B-covers-title", bs.some(function (s) {
  return s.indexOf("very long elastic") >= 0; }));

//  work's wt row: the subject(+pad) is ONE `B` span (the REAL emitRows; the
//  full forest fixture is test/work/view's — too heavy to rebuild here).
check("work-exports-emitRows", typeof work.emitRows === "function");
if (typeof work.emitRows === "function") {
  const fed = [];
  const sink = { feed: function (banner, body, toks) { fed.push({ body: body, toks: toks }); } };
  work.emitRows(sink, [{ rails: "", wt: {
    key: "TKT-1", sha: "0123456789abcdef0123456789abcdef01234567", ts: 0n,
    subject: "an elastic commit subject", counts: null, node: null, mark: "" } }], true);
  const wb = fed.length === 1 ? bTexts(fed[0].body, fed[0].toks) : [];
  check("work-subject-tagged-B", wb.length === 1 &&
        wb[0].indexOf("an elastic commit subject") === 0);
}

//  --- 2. the REAL Pager on a pty: no-wrap …-cut + flush-right pad -----------
const pty = tty.openpty();
tty.setSize(pty.slave, ROWS, COLS);
const rb = io.buf(1 << 16);
let frames = "";
function drain() { rb.reset(); const n = io.read(pty.master, rb);
  if (n > 0) frames += utf8.Decode(rb.data().slice()); }
function strip(s) { return s.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, ""); }

globalThis.be = globalThis.be || {};
be.wrap = { todo: false };

const p = new pager.Pager(pty.slave, { color: true,
  be: { cwd: "/", wt_root: undefined, repo: null } });
p.setHunks(hunks);
p.view.wrap = false;                       // no-wrap (the todo/work default)
const saved = tty.raw(pty.slave);
let rows = [], softFrame = "";
try {
  p.render(); drain();
  rows = strip(frames).split("\r\n");

  //  --- 3. soft-wrap ignores `B`: bytes verbatim, no …, no pad --------------
  p.view.wrap = true;
  frames = "";
  p.render(); drain();
  softFrame = strip(frames);
  p.view.wrap = false;                     // back for the click leg
  frames = "";
  p.render(); drain();
} finally {
  tty.cook(pty.slave, saved);
}

const longRow = rows.filter(function (r) { return r.indexOf("ELS-1") >= 0; })[0] || "";
const shortRow = rows.filter(function (r) { return r.indexOf("ELS-2") >= 0; })[0] || "";
//  RED pre-fix: the long row hard-clips at 40 — no `…`, `[done]` eaten.
check("long-row-ellipsis", longRow.indexOf("…") >= 0);
check("long-row-keeps-done", longRow.indexOf("[done]") >= 0);
check("long-row-width-cols", width(longRow) === COLS);
check("long-row-done-flush", longRow.slice(-6) === "[done]");
//  RED pre-fix: the short row ends short of cols — `[done]` not flush right.
check("short-row-width-cols", width(shortRow) === COLS);
check("short-row-done-flush", shortRow.slice(-6) === "[done]");
check("short-row-no-ellipsis", shortRow.indexOf("…") < 0);
//  BRO-036 r2 (gritzko): the pad renders as the work-view DOTTED leader —
//  `title ┄┄┄ [done]`: one breathing space each side, never a space run.
check("short-row-dot-pad", /tiny ┄+ \[done\]$/.test(shortRow));
check("short-row-no-space-run", !/ {2}/.test(shortRow));

//  Soft-wrap: no elastic chrome; the whole title survives verbatim across the
//  wrapped rows (join without the row breaks to see it contiguously).
check("softwrap-no-ellipsis", softFrame.indexOf("…") < 0);
check("softwrap-no-dots", softFrame.indexOf("┄") < 0);   // pad is no-wrap-only
check("softwrap-title-verbatim",
      softFrame.split("\r\n").join("").indexOf(
        "a very long elastic ticket title that runs far past forty columns") >= 0);

//  --- 4. the REAL click path on the flush-right [done] ----------------------
//  Screen rows are 1-based; the frame rows array mirrors the display order.
const shortScreenRow = rows.indexOf(shortRow) + 1;
const hit = p._screenToByte(shortScreenRow, COLS - 2);   // inside "[done]"
check("click-maps-flush-done", hit !== null);
const uri = hit ? p._uriAt(hit.hunk, hit.off) : null;
check("click-done-spell", uri === "done ELS-2");
//  BRO-036 r2: a click on the ┄ pad itself maps to NO byte (dead cell).
const padCol = Array.from(shortRow.slice(0, shortRow.indexOf("┄"))).length + 1;
check("click-pad-dead", shortRow.indexOf("┄") > 0 &&
      p._screenToByte(shortScreenRow, padCol) === null);

io.close(pty.master); io.close(pty.slave);
w1("DONE\n");
