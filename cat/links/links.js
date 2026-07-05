//  test/cat/links/links.js — BRO-006 repro: the cat (syntax-highlight) VIEW
//  (be/views/cat/cat.js) must emit `U` click-targets on its name/symbol
//  tokens, so the bro pager's left-click consumer (views/bro/pager.js
//  `_uriAt`/`_screenToByte`) can navigate.
//
//  The C cat/file-view (bro/BRO.c `BROTokenize`) emits ONLY syntax-colour
//  tags — NO per-token `U` (its 8 `'U'` sites are all CONSUMERS).  The only
//  symbol nav the C file view performs is the right-click `grep:#<word>` over
//  the GREPABLE token under the cursor (bro_word_around → BRO.c:2968/1108-1113;
//  grepable = bytes hold a word char [A-Za-z0-9_] or a >=0x80 byte).  BRO-006
//  ports THAT to a left-click `U` target: every grepable token gets a
//  following `U` token whose hidden TEXT bytes are `grep:#<token>`, matching
//  the `_uriAt` contract (visible tok → `U` tok → URI bytes).  The JS
//  `tok.parse` binding runs the base lexer only (no DEFMark), so identifiers
//  are `S`, not `N`/`C` — the predicate is byte-level.  Cross-file definition
//  jumps need a symbol index cat.js lacks — deferred (see the ticket).
//
//    RED  (pre-fix): cat.js emits no `U` token → no nav target.
//    GREEN (post-fix): grepable tokens carry `U` → the `grep #<token>` spell
//                      (URI-014 word-URI shape); visible plain text unchanged.

"use strict";

const { eq, ok, bytesEq } = require("../../lib/assert.js");
const cat = require("views/cat/cat.js");

const TMP = io.getenv("TMP") || "/tmp";
const wt = TMP + "/cat006-links-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
io.mkdir(wt);

//  A tiny C file: a function definition (`add`, an `N` token) that CALLS a
//  function (`puts`, a `C` token) — the two symbol-token kinds DEFMark tags.
const SRC = "int add(int a, int b) {\n    puts(\"hi\");\n    return a + b;\n}\n";
const path = "add.c";
(function writeFile(p, bytes) {
  const fd = io.open(p, "c");
  const b = io.buf(bytes.length + 8); b.feed(bytes); io.writeAll(fd, b);
  io.close(fd);
})(wt + "/" + path, utf8.Encode(SRC));

//  --- drive cat.js with a stub sink that captures the feed ----------------
const feeds = [];
const sink = { feed: function (uri, body, toks, verb, ts) {
  feeds.push({ uri: uri, body: body, toks: toks, verb: verb });
} };
function run(mode) {
  feeds.length = 0;
  //  JAB-004: cat is plain-args reading the global `be` — mint it, then call plain.
  globalThis.be = { repo: { wt: wt, storePath: wt, project: "p" },
                    sink: sink, format: mode, out: null, flags: [] };
  cat("cat:" + path);
}

//  tok helpers (the JS tok-build model, log.js): [31..27] tag, [23..0] end.
function tag(w) { return String.fromCharCode(65 + ((w >>> 27) & 0x1f)); }
function end(w) { return w & 0xffffff; }

//  --- COLOR mode: the toks carry the symbol tokens + their `U` targets ----
run("color");
ok(feeds.length >= 1, "cat emitted at least one hunk");
const hk = feeds[0];
const toks = hk.toks;
ok(toks.length > 0, "color hunk carries tok32 spans");

//  Collect every (visible-token, following-U-target-URI) pair, the EXACT
//  way _uriAt reads it: a `U` tok's hidden bytes are [prevEnd..end).
const links = [];   // { sym, uri }
for (let i = 1; i < toks.length; i++) {
  if (tag(toks[i]) !== "U") continue;
  const lo = end(toks[i - 1]);          // prev tok end = U bytes start
  const hi = end(toks[i]);              // U tok end = U bytes end
  ok(hi > lo, "U target has non-empty hidden bytes");
  const prevTag = i >= 2 ? tag(toks[i - 2]) : "S";   // the VISIBLE token's tag
  links.push({ visTag: prevTag, uri: utf8.Decode(hk.body.slice(lo, hi)),
               vis: utf8.Decode(hk.body.slice(i >= 2 ? end(toks[i - 2]) : 0, lo)) });
}

//  THE REPRO: the `add` identifier and the `puts` call must each get a `U`
//  target — pre-fix there are ZERO `U` tokens, so links is empty (RED).
ok(links.length > 0, "BRO-006: cat emits at least one U click-target");

//  URI-014: every U target is the `word URI` spell `grep #<word>` (verb OUT of
//  the scheme; C right-click was `grep:#<word>` — now the space-separated spell).
function findSym(sym) {
  for (const l of links) if (l.uri === "grep #" + sym) return l;
  return null;
}
ok(findSym("add"),    "URI-014: the `add` identifier carries U -> grep #add");
ok(findSym("puts"),   "URI-014: the `puts` call carries U -> grep #puts");
ok(findSym("int"),    "URI-014: the `int` keyword carries U -> grep #int");
ok(findSym("return"), "URI-014: the `return` keyword carries U -> grep #return");

//  Pure-punctuation / whitespace tokens get NO U (not grepable): the `U`
//  count equals the grepable-token count, never the total token count.  Each
//  target is the `grep #<word>` spell (URI-014: "grep #" prefix, 6 bytes).
for (const l of links)
  ok(/^grep #/.test(l.uri) && /[A-Za-z0-9_]/.test(l.uri.slice(6)),
     "every U target is grep #<word>, got " + l.uri);

//  --- PLAIN output is unchanged: the U bytes stay HIDDEN ------------------
//  The hunk BODY is the SAME bytes in both modes (U bytes live in body only
//  when toks reference them; the visible text the pager renders skips them).
//  cat.js feeds the raw file bytes as the body in plain mode (no toks) — the
//  visible bytes must be byte-identical to the source.
run("plain");
const pbody = feeds[0].body;
//  plain body == the raw source bytes (no U bytes appended, no toks).
bytesEq(pbody, utf8.Encode(SRC), "plain body is the verbatim source (no U bytes)");
eq(feeds[0].toks.length, 0, "plain mode emits no toks (and so no U bytes)");

//  --- COLOR visible text (U bytes skipped) still reconstructs the source --
//  Walk the color hunk the way pager.paintRow does: emit every byte NOT
//  covered by a `U` token; the result must equal the original source bytes.
function visibleBytes(body, toks) {
  const out = [];
  let ti = 0, pos = 0;
  while (pos < body.length) {
    while (ti < toks.length && end(toks[ti]) <= pos) ti++;
    const t = ti < toks.length ? tag(toks[ti]) : "S";
    if (t === "U") { pos++; continue; }     // hidden cell
    out.push(body[pos]); pos++;
  }
  return new Uint8Array(out);
}
run("color");
const vis = visibleBytes(feeds[0].body, feeds[0].toks);
bytesEq(vis, utf8.Encode(SRC), "color visible bytes reconstruct the source (U hidden)");

//  cleanup
try { io.unlink(wt + "/" + path); } catch (e) {}

io.log("cat/links.js OK\n");
