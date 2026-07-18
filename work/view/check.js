//  test/work/view/check.js — WORK-001 assert: the `work` FOREST's pager chrome
//  (review 2026-07-18 form).
//
//  argv[2] = captured `jab work --tlv` bytes (a file).  Wt row layout:
//  `//KEY  [get] [diff] [post]  <ahbeh8>  <time5> #<hashlet8> <subject≤30>
//  [done] [dont]` — buttons named for their verbs right after the key ([get]
//  blue 'Y', [diff] yellow 'E', [post] green 'W'), ahbeh behind/ahead colored
//  ('M'/'G'), [done]/[dont] after the message minting `//KEY/: done .` /
//  `//KEY/: dont .` (the BE-044 slot reshaped: mv + ticket flip).  Main-tree
//  repo rows (root + mounts) are BOLD ('C'); tracker wt keys unstyled ('S').
//  Hidden bytes never leak into the visible text; a REAL mouse press drives
//  the BRO-025 dispatch (_feed → parseOspell → _actSpell(spell, //KEY)).
"use strict";

const pager = require("views/bro/pager.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }

const tlvPath = process.argv[2];
const st = io.lstat(tlvPath);
const sz = Number(st.size);
const fd = io.open(tlvPath, "r");
const rb = io.buf(sz + 16);
io.readAll(fd, rb, sz);
io.close(fd);
const tlv = rb.data().slice();

const hunks = pager.hunksFromTlv(tlv);
ok(hunks.length >= 3, "work produced the three tree hunks, got " + hunks.length);

function tagOf(w) { return String.fromCharCode(65 + ((w >>> 27) & 0x1f)); }
function endOf(w) { return w & 0xffffff; }

//  Every hunk token as { tag, text } in stream order (hidden U/O included).
function tokens(text, toks) {
  const out = [];
  let prev = 0;
  for (let i = 0; i < toks.length; i++) {
    const end = endOf(toks[i]);
    out.push({ tag: tagOf(toks[i]), text: utf8.Decode(text.slice(prev, end)) });
    prev = end;
  }
  return out;
}

let toks = [];
let visible = "";
for (const h of hunks) {
  const tt = tokens(h.text, h.toks || new Uint32Array(0));
  toks = toks.concat(tt);
  for (const t of tt) if (t.tag !== "U" && t.tag !== "O") visible += t.text;
}
ok(visible.indexOf("status //") < 0 && visible.indexOf("get ///") < 0 &&
   visible.indexOf("post '") < 0 && visible.indexOf("diff //") < 0 &&
   visible.indexOf("done .") < 0 && visible.indexOf("dont .") < 0 &&
   visible.indexOf("/: ") < 0, "a hidden spell leaked into visible text");
ok(visible.indexOf("[rm -rf]") < 0 && visible.indexOf("[update]") < 0 &&
   visible.indexOf("[merge]") < 0, "a retired button label survived");

//  pair(vText, vTag, hTag, hSpell): a visible `vText` token (of tag vTag when
//  given) immediately followed by the hidden `hTag` token carrying `hSpell`.
function pairAt(i, vText, vTag, hTag, hSpell) {
  return toks[i].text === vText && toks[i].tag !== "U" && toks[i].tag !== "O" &&
         (!vTag || toks[i].tag === vTag) &&
         i + 1 < toks.length && toks[i + 1].tag === hTag && toks[i + 1].text === hSpell;
}
function hasPair(vText, vTag, hTag, hSpell) {
  for (let i = 0; i < toks.length; i++) if (pairAt(i, vText, vTag, hTag, hSpell)) return true;
  return false;
}
function idxOf(vText, hTag, hSpell) {
  for (let i = 0; i < toks.length; i++) if (pairAt(i, vText, null, hTag, hSpell)) return i;
  return -1;
}

//  --- wt-row U navs (all blocks), keys UNSTYLED ('S') ---------------------
for (const key of ["TRK-5", "PIN-1", "BR-2", "DET-3", "FOR-4"])
  ok(hasPair("//" + key, "S", "U", "status //" + key),
     key + " row lacks an unstyled key + U `status //" + key + "`");
//  Repo rows BOLD ('C') + their own status navs.
ok(hasPair("vend/ext", "C", "U", "status vend/ext"), "vend/ext mount row not bold/nav'd");
ok(hasPair("deep", "C", "U", "status vend/ext/deep"), "deep mount row not bold/nav'd");
ok(hasPair("meta", "C", "U", "status"), "root row not bold/nav'd");

//  --- the buttons: verb names, colors, BRO-025 three-part O invites -------
ok(hasPair("[get]", "Y", "O", "//TRK-5/: get ///vend/ext"),
   "TRK-5 [get] lacks blue Y + O `//TRK-5/: get ///vend/ext`");
ok(hasPair("[get]", "Y", "O", "//PIN-1/: get ///vend/ext"),
   "PIN-1 [get] lacks blue Y + O `//PIN-1/: get ///vend/ext`");
ok(hasPair("[diff]", "E", "U", "diff //PIN-1"),
   "PIN-1 [diff] lacks yellow E + U `diff //PIN-1`");
ok(hasPair("[post]", "W", "O", "//PIN-1/: post 'PIN-1: pin sample ticket'"),
   "PIN-1 [post] lacks green W + O `//PIN-1/: post '<ticket title>'`");
ok(hasPair("[done]", null, "O", "//PIN-1/: done ."),
   "PIN-1 [done] lacks O `//PIN-1/: done .`");
ok(hasPair("[dont]", null, "O", "//PIN-1/: dont ."),
   "PIN-1 [dont] lacks O `//PIN-1/: dont .`");
ok(hasPair("[done]", null, "O", "//FOR-4/: done ."),
   "FOR-4 [done] lacks O `//FOR-4/: done .`");
//  Non-block-1 wts hang under no mount -> NO [get]; FOR-4 has no ticket page
//  -> NO [post]; the [rm -rf] spell is retired everywhere.
for (const t of toks) {
  if (t.tag !== "O") continue;
  if (t.text.indexOf("//BR-2/: get") === 0 || t.text.indexOf("//DET-3/: get") === 0 ||
      t.text.indexOf("//FOR-4/: get") === 0 || t.text.indexOf("//FOR-4/: post") === 0)
    fail("a non-block-1 wt grew a [get]/[post] spell: " + t.text);
  if (t.text.indexOf("rm ") >= 0) fail("a retired rm spell survived: " + t.text);
}

//  --- button placement: [get] right after the key, [done] after the message --
const iKey  = idxOf("//PIN-1", "U", "status //PIN-1");
const iGet  = idxOf("[get]", "O", "//PIN-1/: get ///vend/ext");
const iDiff = idxOf("[diff]", "U", "diff //PIN-1");
const iPost = idxOf("[post]", "O", "//PIN-1/: post 'PIN-1: pin sample ticket'");
const iDone = idxOf("[done]", "O", "//PIN-1/: done .");
const iDont = idxOf("[dont]", "O", "//PIN-1/: dont .");
ok(iKey >= 0 && iGet > iKey && iDiff > iGet && iPost > iDiff &&
   iDone > iPost && iDont > iDone,
   "PIN-1 button order is not key<[get]<[diff]<[post]<…<[done]<[dont]");
//  Between the key and [get]: only the dotted leader / spacers (r2 filler).
for (let i = iKey + 2; i < iGet; i++)
  ok(/^[ ┄]+$/.test(toks[i].text),
     "non-filler between the key and [get]: '" + toks[i].text + "'");

//  --- r2: NAME-only bold, one dotted leader per row, aligned columns --------
//  Every C (bold) token is exactly a repo NAME — never a date/hash/msg tail.
const NAMES = { meta: 1, "vend/ext": 1, deep: 1 };
for (const t of toks)
  if (t.tag === "C" && !NAMES[t.text])
    fail("a non-name token rides the bold C tag: '" + t.text + "'");
ok(visible.indexOf("//PIN-1 ┄") >= 0, "the //PIN-1 row lacks its dotted leader");
//  Alignment: [diff] and the #hashlet sit at ONE visible column on EVERY row
//  that has them (KEYW + fixed button slots — chars, not bytes).
{
  let diffCol = -1, hashCol = -1;
  for (const s of visible.split("\n")) {
    const di = s.indexOf("[diff]");
    if (di >= 0) {
      const col = Array.from(s.slice(0, di)).length;
      if (diffCol < 0) diffCol = col;
      else if (col !== diffCol) fail("[diff] column drifts: " + col + " vs " + diffCol);
    }
    const hm = s.match(/#[0-9a-f]{8}/);
    if (hm) {
      const col = Array.from(s.slice(0, hm.index)).length;
      if (hashCol < 0) hashCol = col;
      else if (col !== hashCol) fail("#hashlet column drifts: " + col + " vs " + hashCol);
    }
  }
  ok(diffCol >= 0 && hashCol > diffCol, "no aligned [diff]/#hashlet columns found");
}

//  --- the ahbeh column: behind 'M' (salmon slot), ahead 'G' (salad slot) ----
function hasTagged(tag, text) {
  for (const t of toks) if (t.tag === tag && t.text === text) return true;
  return false;
}
ok(hasTagged("M", "-1"), "PIN-1's behind count lacks the 'M' span");
ok(hasTagged("G", "+1"), "BR-2's ahead count lacks the 'G' span");

//  --- the REAL click path (the rowclick model): a mouse press on a button ---
//  Drives Pager._feed with a raw SGR mouse press so the BRO-025 dispatch runs
//  for real: _screenToByte -> _uriAt -> parseOspell -> the isMutation gate ->
//  _actSpell(spell, context) — the row's OWN `//KEY` context, never the pager's.
const COLS = 500;
const realSize = tty.size;
tty.size = function () { return { rows: 200, cols: COLS }; };
const p = new pager.Pager(-1, { color: false,
                                driveSpell: function () { return []; },
                                isMutation: function (v) {
                                  return v === "done" || v === "dont" ||
                                         v === "get" || v === "post"; } });
p.setHunks(hunks);
const rows = p.rows(COLS);
const acts = [], runs = [];
p._actSpell = function (s, ctx) { acts.push([s, ctx]); };
p._runSpell = function (s, ctx) { runs.push([s, ctx]); };
function cellOf(spell) {
  for (let dr = 0; dr < rows.length; dr++)
    for (let col = 1; col <= COLS; col++) {
      const hit = p._screenToByte(dr + 1, col);
      if (!hit) break;                            // past end-of-line
      if (p._uriAt(hit.hunk, hit.off) === spell) return { row: dr + 1, col: col };
    }
  return null;
}
function click(cell) {
  p._feed(utf8.Encode("\x1b[<0;" + cell.col + ";" + cell.row + "M"));
}
const doneCell = cellOf("//PIN-1/: done .");
ok(doneCell, "no clickable [done] cell resolves to `//PIN-1/: done .`");
click(doneCell);
ok(acts.length === 1 && acts[0][0] === "done ." && acts[0][1] === "//PIN-1",
   "the [done] click must _actSpell(`done .`, `//PIN-1`), got " + JSON.stringify(acts));
const navCell = cellOf("status //BR-2");
ok(navCell, "no clickable cell resolves to `status //BR-2`");
click(navCell);
ok(runs.length === 1 && runs[0][0] === "status //BR-2" && runs[0][1] === undefined,
   "the key click must _runSpell(`status //BR-2`) context-less, got " + JSON.stringify(runs));
tty.size = realSize;

io.log("test/work/view OK (" + toks.length + " tokens)\n");
