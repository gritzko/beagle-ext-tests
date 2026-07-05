//  test/commit/links/check.js — BRO-006 repro/assert: `jab commit:?<sha>` must
//  emit a `U` click-target after the `tree` and `parent` sha values, the
//  producer half of BRO-005 mouse nav.  Mirrors C keeper KEEPProjCommit
//  (PROJ.c:468-493): `tree <sha>` → `tree:?<sha40>`, `parent <sha>` →
//  `commit:?<sha40>` (open the parent); the synthetic `commit <sha>` header is
//  the page itself and carries NO `U` (PROJ.c:431-436).
//
//  argv[2] = captured `jab commit:?<sha> --tlv` bytes (a file).
//  argv[3] = expected tree:?<sha40>      argv[4] = expected commit:?<sha40>.
//  Reparses the TLV via the pager's own hunksFromTlv, then for EACH `U` token
//  decodes its hidden URI bytes AND verifies the pager `_uriAt` left-click on
//  the preceding sha token resolves to the same URI (the exact consumer path).
//  Also asserts COMMIT-003/004/005: the VISIBLE text (U bytes hidden) reads the
//  plain metadata, no `:?` URI bytes leak, and the `commit ` line has no U.
//    RED  (pre-fix): the commit view emits NO `U` token → no nav target.
//    GREEN (post-fix): tree → tree:?<sha>, parent → commit:?<sha>.
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

//  URI-014: the expected U-targets are WORD-URI spells (`tree ?<sha>`,
//  `commit ?<sha>`) — the verb OUT of the scheme, a SPACE before the addressing.
const wantTree   = process.argv[3];
const wantParent = process.argv[4];
ok(wantTree && wantTree.indexOf("tree ?") === 0, "expected tree ?<sha> arg");
ok(wantParent && wantParent.indexOf("commit ?") === 0, "expected commit ?<sha> arg");

const hunks = pager.hunksFromTlv(tlv);
//  COMMIT-006: the metadata is the FIRST hunk; a non-merge commit now relays
//  its inline diff as FURTHER hunks after it (native `be commit: --tlv` emits
//  the same 2: metadata + diff:<path>).  The U-target assertions below operate
//  on hunks[0] (the metadata) — the diff hunks carry their own diff: U targets.
ok(hunks.length >= 1, "commit view feeds the metadata hunk first");

function tagOf(w) { return String.fromCharCode(65 + ((w >>> 27) & 0x1f)); }
function endOf(w) { return w & 0xffffff; }

//  The VISIBLE text (drop every `U`-tagged span) — must read the plain metadata
//  COMMIT-003/004/005 produced, with no hidden URI bytes leaking through.
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

const h = hunks[0];
const text = h.text, toks = h.toks;
ok(toks.length > 0, "color/tlv hunk carries tok32 spans");

//  Collect every `U` target + the URI a click on its preceding token resolves to
//  (the pager `_uriAt` contract: visible tok → `U` tok → hidden URI bytes).
const targets = [];
for (let i = 0; i < toks.length; i++) {
  if (tagOf(toks[i]) !== "U") continue;
  const lo = i > 0 ? endOf(toks[i - 1]) : 0;
  const hi = endOf(toks[i]);
  ok(hi > lo, "U span non-empty at tok " + i);
  const uri = utf8.Decode(text.slice(lo, hi));
  //  A click on the last byte of the preceding (sha) token must resolve here.
  const click = pager.Pager.prototype._uriAt.call({}, { text: text, toks: toks }, lo - 1);
  eq(click, uri, "_uriAt(sha) resolves the same URI for " + uri);
  targets.push(uri);
}

//  Exactly two U targets: tree (tree ?<sha>) and parent (commit ?<sha>).  The
//  synthetic `commit <sha>` header carries NO U (it IS the page).
eq(targets.length, 2, "exactly two U targets (tree + parent)");
eq(targets[0], wantTree,   "tree sha → tree ?<sha40>");
eq(targets[1], wantParent, "parent sha → commit ?<sha40>");

//  COMMIT-003/004/005 preservation: the visible text is the plain metadata, the
//  `commit ` line stays first with no U leak, and no URI-014 spell bytes show.
const vis = visibleText(text, toks);
ok(vis.indexOf("commit " + wantParent.slice("commit ?".length)) !== 0,
   "the synthetic commit line is the resolved sha, not the parent");
ok(vis.indexOf("\ntree ") >= 0, "visible tree header survives");
ok(vis.indexOf("\nparent ") >= 0, "visible parent header survives");
ok(vis.indexOf("\nauthor ") >= 0, "visible author header survives");
//  URI-014: the hidden spell is `<verb> ?<sha>` — assert neither it nor the
//  retired scheme `:?` form leaks into the visible metadata text.
ok(vis.indexOf(" ?") < 0 && vis.indexOf(":?") < 0,
   "U URI bytes stay hidden from the visible text");

io.log("test/commit/links OK (tree+parent U targets, U hidden)\n");
