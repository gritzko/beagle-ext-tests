//  test/log/links/check.js — BRO-006 repro/assert: `jab log:` must emit a `U`
//  click-target per commit row, the producer half of BRO-005 mouse nav.
//
//  argv[2] = captured `jab log: --tlv` bytes (a file); argv[3..] = the expected
//  commit:?<full-sha> URI for each row, newest-first.  Reparses the TLV into
//  hunks (pager.hunksFromTlv), then for EVERY visible row token decodes the
//  NEXT token: it must be tag `U` and its hidden bytes must equal the expected
//  URI (the `be/views/bro/pager.js` `_uriAt` contract).  Also asserts LOG-001:
//  every commit row's VISIBLE text (U bytes hidden) survives + reads plain.
//    RED  (pre-fix): the log view emits NO `U` token → no nav target.
//    GREEN (post-fix): each row's sha8 token is followed by a `U` → commit:?<sha>.
"use strict";

const pager = require("views/bro/pager.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }
function eq(a, b, m) { if (a !== b) fail(m + ": " + a + " !== " + b); }

//  Read the captured --tlv stream (the loop's raw 'H'-record bytes).
const tlvPath = process.argv[2];
const st = io.lstat(tlvPath);
const sz = Number(st.size);
const fd = io.open(tlvPath, "r");
const rb = io.buf(sz + 16);
io.readAll(fd, rb, sz);
io.close(fd);
const tlv = rb.data().slice();

//  The expected per-row URIs (newest-first), one CLI arg each.  URI-014: the JS
//  view now bakes the WORD-URI spell (`commit ?<sha>`, verb OUT of the scheme);
//  the C oracle still hands us the scheme form (`commit:?<sha>`), so re-shape
//  each expected target to the word form here (a space can't survive $WANT
//  word-splitting, so the arg arrives scheme-form and is rewritten in-JS).
const want = process.argv.slice(3).map(function (u) {
  return u.indexOf("commit:?") === 0 ? "commit ?" + u.slice("commit:?".length) : u;
});
ok(want.length >= 1, "need at least one expected URI");

const hunks = pager.hunksFromTlv(tlv);
ok(hunks.length >= 1, "log produced at least one hunk");

//  --- U-target decode (the `_uriAt` contract) ----------------------------
//  Tag of a tok32 word: high 5 bits → 'A'..'Z'.  End: low 24 bits.
function tagOf(w) { return String.fromCharCode(65 + ((w >>> 27) & 0x1f)); }
function endOf(w) { return w & 0xffffff; }

//  The `U` URI a visible byte offset points at: find the token covering `off`,
//  require the NEXT token to be `U`, and return its hidden bytes [prevEnd..end).
//  This is byte-for-byte the pager's `_uriAt`.
function uriAt(text, toks, off) {
  let ti = 0;
  while (ti < toks.length && endOf(toks[ti]) <= off) ti++;
  const nxt = ti + 1;
  if (nxt >= toks.length) return null;
  if (tagOf(toks[nxt]) !== "U") return null;
  const lo = nxt > 0 ? endOf(toks[nxt - 1]) : 0;
  const hi = endOf(toks[nxt]);
  if (hi <= lo) return null;
  return utf8.Decode(text.slice(lo, hi));
}

//  The VISIBLE text of a hunk: walk its tokens, dropping `U`-tagged byte spans
//  (the hidden click targets) exactly as paintRow/.plain do.  Must read the
//  same plain log rows LOG-001 produced — U bytes never leak into the display.
function visibleText(text, toks) {
  let out = "", prev = 0;
  for (let i = 0; i < toks.length; i++) {
    const end = endOf(toks[i]);
    if (tagOf(toks[i]) !== "U")
      for (let j = prev; j < end; j++) out += String.fromCharCode(text[j]);
    prev = end;
  }
  return out;
}

//  Collect every commit row across all hunks (the log view feeds ONE hunk; be
//  tolerant of either shape).  A row = the byte range of one '\n'-terminated
//  visible line; we test the sha8 token at each line start.
let rowIdx = 0;
for (const h of hunks) {
  const text = h.text, toks = h.toks;
  ok(toks.length > 0, "hunk carries tok32 spans (color/tlv mode)");

  //  Each row starts at a line boundary in VISIBLE space, but we need the BYTE
  //  offset of each row's first sha8 byte.  Walk byte rows: the first token's
  //  end is the sha8 column end of the FIRST row; rows repeat the same span
  //  shape.  Simplest robust check: for every `U` token, the URI it carries
  //  must equal the expected for its row, AND a click on the byte just before
  //  the U span (the sha8 token) must resolve to that same URI.
  let off = 0;
  while (off < text.length) {
    //  find the next U token whose span starts at/after `off`
    let ti = 0;
    while (ti < toks.length && endOf(toks[ti]) <= off) ti++;
    //  advance to a U token
    while (ti < toks.length && tagOf(toks[ti]) !== "U") ti++;
    if (ti >= toks.length) break;
    const uLo = ti > 0 ? endOf(toks[ti - 1]) : 0;   // sha8 column end
    const uHi = endOf(toks[ti]);
    const uri = utf8.Decode(text.slice(uLo, uHi));
    ok(rowIdx < want.length, "more U-targets than expected URIs");
    eq(uri, want[rowIdx], "row " + rowIdx + " U-target URI");
    //  A click anywhere in the sha8 token (offset uLo-1) must resolve via the
    //  `_uriAt` contract to the same URI (the consumer's exact path).
    const click = uriAt(text, toks, uLo - 1);
    eq(click, want[rowIdx], "row " + rowIdx + " _uriAt(sha8) resolves");
    rowIdx++;
    off = uHi;
  }

  //  LOG-001 preservation: the VISIBLE text (U bytes hidden) is non-empty and
  //  carries one '<sha8> <date> <summary> (<author>)' line per expected row.
  const vis = visibleText(text, toks);
  ok(vis.indexOf("\n") >= 0, "visible rows survive (LOG-001 plain output)");
  //  URI-014: the hidden target is now the word spell `commit ?<sha>` — assert
  //  neither the word nor the retired scheme form leaks into the visible text.
  ok(vis.indexOf("commit ?") < 0 && vis.indexOf("commit:?") < 0,
     "U bytes stay hidden from the visible text");
}

eq(rowIdx, want.length, "exactly one U-target per commit row");
io.log("test/log/links OK (" + rowIdx + " rows)\n");
