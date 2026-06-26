//  test/bro/rowclick/check.js — BRO-005 follow-up: drive the Pager's mouse-click
//  path over a real `jab log: --tlv` capture and assert EVERY commit row is
//  clickable across its WHOLE span (sha8 + date + summary + author + soft-wrap
//  tail), each resolving to that row's commit:?<sha>.
//
//  Repro of the live bug: only the 8-char sha token (the one before the `U`)
//  navigated; a click on the date / summary / author / wrapped tail — the bulk
//  of a log row — returned null and the row read as a dead link (fewer than
//  half the visible cells clickable).  RED before the `_uriAt` line-fallback,
//  GREEN after.  Also guards cat-style MANY-U-per-line word links stay token-
//  precise (the line-fallback only fires for a line with exactly one U).
//
//  argv[2] = captured `jab log: --tlv` bytes; argv[3..] = expected
//  commit:?<full-sha> per row, newest-first.
"use strict";

const pager = require("views/bro/pager.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }
function eq(a, b, m) { if (a !== b) fail(m + ": " + a + " !== " + b); }

//  Load the captured --tlv stream into hunks.
const st = io.lstat(process.argv[2]);
const sz = Number(st.size);
const fd = io.open(process.argv[2], "r");
const rb = io.buf(sz + 16);
io.readAll(fd, rb, sz);
io.close(fd);
const hunks = pager.hunksFromTlv(rb.data().slice());
ok(hunks.length >= 1, "log produced at least one hunk");

const want = process.argv.slice(3);
ok(want.length >= 3, "need at least three expected commit URIs");

//  A narrow width so the long commit summaries soft-WRAP — this is the exact
//  shape that exposed the bug (a commit spans 2 display rows; the tail row
//  carries no sha, yet must still navigate to its commit).
const COLS = 40;
const realSize = tty.size;
tty.size = function () { return { rows: 24, cols: COLS }; };

const p = new pager.Pager(-1, { color: false, driveSpell: function () { return []; } });
p.setHunks(hunks);
const rows = p.rows(COLS);

//  Walk the display rows.  Display row 0 is the banner; each body row maps to a
//  screen row (1-based) of scroll(0)+dr+1.  For each row we click several
//  columns: col 1 (sha/tail start) plus a few interior columns spanning the
//  date/summary/author — EACH must resolve to the SAME commit the row belongs
//  to.  The expected commit for a row = the commit:?<sha> of its logical line.
function lineUriExpected(hunk, off) {
  //  The single U on off's logical line, decoded — the oracle the click must hit.
  const text = hunk.text, toks = hunk.toks;
  let lo = off; while (lo > 0 && text[lo - 1] !== 0x0a) lo--;
  let hi = off; while (hi < text.length && text[hi] !== 0x0a) hi++;
  let u = -1, prev = 0;
  for (let i = 0; i < toks.length; i++) {
    const e = toks[i] & 0xffffff;
    if (prev >= lo && prev < hi && String.fromCharCode(65 + ((toks[i] >>> 27) & 0x1f)) === "U") u = i;
    prev = e;
  }
  if (u < 0) return null;
  const a = u > 0 ? (toks[u - 1] & 0xffffff) : 0, b = toks[u] & 0xffffff;
  return utf8.Decode(text.slice(a, b));
}

let shaRows = 0, tailRows = 0;
for (let dr = 1; dr < rows.length; dr++) {
  const r = rows[dr];
  const screenRow = dr + 1;                       // scroll 0, banner is screen 1
  const want_uri = lineUriExpected(r.hunk, r.off);
  //  A row with no U on its logical line (blank lines etc.) is not a commit row.
  const isSha = r.off === 0 || r.hunk.text[r.off - 1] === 0x0a;
  if (want_uri === null) continue;
  if (isSha) shaRows++; else tailRows++;
  //  Click col 1 and several interior columns; each must navigate to want_uri.
  for (const col of [1, 3, 5, 9, 13, 18, 25, 33]) {
    const hit = p._screenToByte(screenRow, col);
    if (!hit) continue;                            // past end-of-line: skip
    const got = p._uriAt(hit.hunk, hit.off);
    eq(got, want_uri, "screenRow " + screenRow + " col " + col + " navigates");
  }
}
ok(shaRows >= 3, "at least three sha-bearing commit rows (" + shaRows + ")");
ok(tailRows >= 1, "at least one soft-wrap tail row is also clickable (" + tailRows + ")");

//  Regression guard: a cat-style line with MANY U word-links stays token-
//  precise — the line-fallback must NOT fire when a line has >1 U, so a click
//  resolves to the WORD it lands on, never a neighbour.
function packTok(tag, end) { return (((tag.charCodeAt(0) - 65) & 0x1f) << 27) | (end & 0xffffff); }
//  "foo bar baz\n": each word an F token immediately followed by its own U link.
const ctext = utf8.Encode("foogrep:#foo bargrep:#bar\n");
const ctoks = Uint32Array.from([
  packTok("F", 3),  packTok("U", 12),             // "foo" + U "grep:#foo"
  packTok("S", 13),                               // " "
  packTok("F", 16), packTok("U", 25),             // "bar" + U "grep:#bar"
  packTok("S", 26),                               // "\n"
]);
const chunk = { uri: "x.txt#L1", verb: "hunk", text: ctext, toks: ctoks, kind: "file" };
const pc = new pager.Pager(-1, { color: false });
eq(pc._uriAt(chunk, 0), "grep:#foo", "cat word-link: click 'foo' -> grep:#foo");
eq(pc._uriAt(chunk, 13), "grep:#bar", "cat word-link: click 'bar' -> grep:#bar");
//  The space (byte 12) sits on an S token whose next token is NOT a U, and the
//  line carries >1 U, so the line-fallback stays silent — token-precision kept.
eq(pc._uriAt(chunk, 12), null, "cat space cell: not a link (multi-U line, no fallback)");

tty.size = realSize;
io.log("test/bro/rowclick OK (" + shaRows + " sha rows, " + tailRows + " tail rows)\n");
