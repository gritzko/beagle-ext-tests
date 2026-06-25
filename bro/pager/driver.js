//  test/js/bro/pager/driver.js — JAB-028 headless checks for the bro pager.
//  The interactive raw-mode loop is hard to drive under ctest, so this driver
//  unit-tests the PIECES that are pure functions of (hunks, keys, bytes):
//    1. hunksFromTlv: a captured --tlv 'H'-record stream reparses to hunks.
//    2. indexAll + paintRow: a hunk stream → display rows (banner + soft-wrap),
//       a row paints plain (verbatim) and colour (carries SGR).
//    3. statusURI/statusPos: the bottom-bar `<path>#L<n>` + TOP/%/BOT.
//    4. the Pager state machine: synthetic keys (j/k/space/g/G/:/Enter) drive
//       scroll + the address bar WITHOUT a tty (we never call run()).
//  argv[2] = path to view/bro/pager.js, argv[3] = path to view/bro.js (lib).
"use strict";
const pager = require(process.argv[2]);
const bro = require(process.argv[3]);

function w(s) {
  const b = utf8.Encode(s);
  const x = io.buf(b.length + 8); x.feed(b); io.writeAll(1, x);
}
function check(name, cond) { w((cond ? "ok   " : "FAIL ") + name + "\n"); }

//  --- 1. tlv round-trip: build a HUNK log, serialize, reparse via the pager ---
const src = utf8.Encode("alpha\nbeta\ngamma\n");
const log = abc.ram("HUNK", 4096);
log.feed("note.txt#L1", src, new Uint32Array(0), "cat", 0n);
const tlv = log.subarray(0, log.buffer.watermark | 0).slice();
const hunks = pager.hunksFromTlv(tlv);
check("tlv-roundtrip-count", hunks.length === 1);
check("tlv-roundtrip-uri", hunks[0].uri === "note.txt#L1");
check("tlv-roundtrip-text", utf8.Decode(hunks[0].text) === "alpha\nbeta\ngamma\n");

//  --- 1b. JAB-030 hunksFromLog: a LIVE HUNK ram log -> hunks (the universal-
//  pager edge path, no tlv serialize round-trip).  Two records, kept distinct.
if (typeof pager.hunksFromLog === "function") {
  const log2 = abc.ram("HUNK", 4096);
  log2.feed("a.txt#L1", utf8.Encode("one\ntwo\n"), new Uint32Array(0), "cat", 0n);
  log2.feed("b.txt#L1", utf8.Encode("three\n"), new Uint32Array(0), "grep", 0n);
  const lh = pager.hunksFromLog(log2);
  check("fromLog-count", lh.length === 2);
  check("fromLog-uri0", lh[0].uri === "a.txt#L1");
  check("fromLog-uri1", lh[1].uri === "b.txt#L1");
  check("fromLog-text0", utf8.Decode(lh[0].text) === "one\ntwo\n");
  check("fromLog-empty", pager.hunksFromLog(null).length === 0);
} else {
  check("fromLog-present", false);   // JAB-030 must export hunksFromLog
}

//  --- 2. indexAll: 1 banner + N body rows; soft-wrap at a narrow width --------
const rowsWide = pager.indexAll(hunks, 80);
check("indexAll-rows", rowsWide.length === 4);          // banner + 3 lines
check("indexAll-banner", rowsWide[0].banner === true);
//  A 3-col width wraps "alpha" (5 cp) into 2 rows → more body rows than lines.
const rowsNarrow = pager.indexAll(hunks, 3);
check("indexAll-softwrap", rowsNarrow.length > 4);

//  --- 2b. paintRow plain == verbatim; colour carries an SGR escape -----------
const body = rowsWide[1];                                // first body row
const plain = pager.paintRow(body.hunk, body.off, body.end, false);
check("paintRow-plain", plain === "alpha");
//  A syntax hunk paints; build one with toks so colour differs from plain.
const code = utf8.Encode('const x = 1;\n');
let toks; try { toks = tok.parse(code, "js"); } catch (e) { toks = new Uint32Array(0); }
const ch = { uri: "x.js#L1", verb: "hunk", text: code, toks: toks, kind: "file" };
const crows = pager.indexAll([ch], 80);
const cplain = pager.paintRow(ch, crows[1].off, crows[1].end, false);
const ccolor = pager.paintRow(ch, crows[1].off, crows[1].end, true);
check("paintRow-color-content", cplain === "const x = 1;");
let hasEsc = false;
for (let i = 0; i < ccolor.length; i++) if (ccolor.charCodeAt(i) === 27) { hasEsc = true; break; }
check("paintRow-color-sgr", toks.length === 0 || hasEsc);   // SGR iff there are toks

//  --- 3. statusURI / statusPos ----------------------------------------------
check("statusURI", bro.statusURI(hunks[0], 2) === "note.txt#L2");
check("statusPos-top", bro.statusPos(0, 100, 10) === "TOP");
check("statusPos-bot", bro.statusPos(90, 100, 10) === "BOT");
check("statusPos-all", bro.statusPos(0, 5, 10) === "ALL");

//  --- 4. Pager state machine (no tty: drive keys directly) -------------------
//  A fake fd whose tty.size we stub by monkey-patching the Pager's width source
//  is overkill; instead use the small page helper indirectly via a big hunk and
//  assert relative scroll moves.  We bypass render() (it needs tty.size) and
//  poke the keys + scroll directly, which is the state we care about.
const big = [];
let txt = "";
for (let i = 0; i < 200; i++) txt += "line " + i + "\n";
big.push({ uri: "big.txt#L1", verb: "hunk", text: utf8.Encode(txt), toks: new Uint32Array(0), kind: "file" });
//  A Pager with a stub fd; we never call run()/render(), only the key handlers,
//  so tty.size is not invoked except by _page() — stub it to a fixed size.
const realSize = tty.size;
tty.size = function () { return { rows: 24, cols: 80 }; };
const p = new pager.Pager(-1, { color: false, driveSpell: function (s) {
  //  the spell drive is mocked: a `mock:` spell yields a one-line hunk.
  if (s.indexOf("mock:") === 0)
    return [{ uri: "mock.txt#L1", verb: "hunk", text: utf8.Encode("mocked\n"),
              toks: new Uint32Array(0), kind: "file" }];
  return [];
} });
p.setHunks(big);
p.rows(80);                                              // index for width 80
check("scroll-start", p.view.scroll === 0);
p.key(0x6a); check("scroll-j", p.view.scroll === 1);     // j  down 1
p.key(0x6b); check("scroll-k", p.view.scroll === 0);     // k  up 1
p.key(0x20); check("scroll-space", p.view.scroll === 22); // space  page (24-2)
p.key(0x67); check("scroll-g", p.view.scroll === 0);     // g  top
p.key(0x47); check("scroll-G", p.view.scroll > 100);     // G  bottom (clamped later)
p.key(0x71); check("key-q", p.quit === true);            // q  quit

//  Address bar: ':' opens command mode, types a spell, Enter runs it (mocked).
const p2 = new pager.Pager(-1, { color: false, driveSpell: p._noop || function (s) {
  if (s.indexOf("mock:") === 0)
    return [{ uri: "mock.txt#L1", verb: "hunk", text: utf8.Encode("mocked\n"),
              toks: new Uint32Array(0), kind: "file" }];
  return [];
} });
p2.setHunks(big);
p2.key(0x3a); check("addr-open", p2.mode === "command");
for (const c of "mock:x") p2.key(c.charCodeAt(0));
check("addr-typed", p2.cmd === "mock:x");
p2.key(0x7f); check("addr-backspace", p2.cmd === "mock:");
p2.key(0x0d); check("addr-enter-mode", p2.mode === "scroll");
check("addr-enter-swap", p2.view.hunks.length === 1 && p2.view.hunks[0].uri === "mock.txt#L1");

//  Esc cancels the address bar without running.
const p3 = new pager.Pager(-1, { color: false });
p3.setHunks(big);
p3.key(0x3a); p3.key(0x1b);
check("addr-esc", p3.mode === "scroll" && p3.cmd === "");

tty.size = realSize;                                     // restore the stub
w("DONE\n");
