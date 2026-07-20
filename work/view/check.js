//  test/work/view/check.js — WORK-001 assert: the `work` FOREST's pager chrome
//  (review 2026-07-18 form).
//
//  argv[2] = captured `jab work --tlv` bytes (a file).  WORK-004 wt row layout:
//  `//KEY  [diff] [post]  [+N][-N]  <time5> #<hashlet8> <subject≤30> [done]
//  [dont]` — [diff] yellow 'E', [post] green 'W'; the ahbeh counts ARE buttons:
//  `[+N]` salad 'G' mints bare `post` (advance track), `[-N]` salmon 'A' mints
//  bare `get` (pull), each a `//KEY/: verb` O-invite; [get] is RETIRED.
//  [done]/[dont] after the message mint `//KEY/: done .` / `//KEY/: dont .`.
//  Main-tree repo rows (root + mounts) are BOLD ('C'); tracker wt keys 'S'.
//  Hidden bytes never leak into the visible text; a REAL mouse press drives
//  the BRO-025 dispatch (_feed → parseOspell → _actSpell(spell, //KEY)).
"use strict";

const pager = require("views/bro/pager.js");
const bro = require("view/bro.js");             // WORK-005: the real pager paint

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
//  WORK-004: [get] is retired; the ahbeh counts became buttons — `[+N]` (salad
//  'A') mints bare `post`, `[-N]` (salmon 'M') mints bare `get`, in the ROW ctx.
//  WORK-010: [diff] compacts to the `[±]` face (SAME `diff //KEY` verb).
ok(hasPair("[±]", "E", "U", "diff //PIN-1"),
   "PIN-1 [±] lacks yellow E + U `diff //PIN-1`");
ok(visible.indexOf("[diff]") < 0, "the old wide [diff] face survived WORK-010");
//  WORK-010 RULING (gritzko): the `[?]` is the cyan 'V' face + a hidden 'O'
//  invite with EMPTY context, verb `todo`, the ticket key as ARG — `//: todo KEY`
//  (a page must exist); a TOPIC-named wt mints `//: todo TOPIC` (the topic dir).
//  rowHelp(key): the [?] O-invite bytes on wt row `key` ("" when the row has none).
function rowHelp(key) {
  for (let i = 0; i < toks.length; i++) {
    if (!(toks[i].tag === "S" && toks[i].text === "//" + key)) continue;
    for (let j = i + 1; j < toks.length; j++) {
      if (toks[j].text === "\n") break;                 // row boundary
      if (toks[j].text === "[?]" && toks[j].tag === "V" &&
          j + 1 < toks.length && toks[j + 1].tag === "O") return toks[j + 1].text;
    }
    return "";                                          // row found, no [?]
  }
  return "";
}
ok(rowHelp("PIN-1") === "//: todo PIN-1",
   "ticket-named PIN-1 [?] must mint `//: todo PIN-1`, got '" + rowHelp("PIN-1") + "'");
ok(rowHelp("DET-3") === "//: todo DET-3",
   "ticket-named DET-3 [?] must mint `//: todo DET-3`, got '" + rowHelp("DET-3") + "'");
ok(rowHelp("PIN") === "//: todo PIN",
   "topic-named PIN [?] must mint `//: todo PIN`, got '" + rowHelp("PIN") + "'");
//  WORK-010 (ruling 2): SUFFIXED ticket names (letter PIN-1b, `-word` PIN-1-retry)
//  are ticket-named too; the [?] mints the BASE ticket link `//: todo PIN-1`.
ok(rowHelp("PIN-1b") === "//: todo PIN-1",
   "suffixed PIN-1b [?] must mint the base `//: todo PIN-1`, got '" + rowHelp("PIN-1b") + "'");
ok(rowHelp("PIN-1-retry") === "//: todo PIN-1",
   "suffixed PIN-1-retry [?] must mint base `//: todo PIN-1`, got '" + rowHelp("PIN-1-retry") + "'");
//  A non-ticket-named wt (TRK/FOR/WT — no board topic, no page) grows NO [?].
for (const key of ["TRK-5", "FOR-4", "WT-A", "WT-B", "PINP-6"])
  ok(rowHelp(key) === "", key + " (non-ticket) must have NO [?], got '" + rowHelp(key) + "'");
for (const t of toks)
  if (t.tag === "O" && /^\/\/: todo (TRK|FOR|WT)/.test(t.text))
    fail("a non-ticket wt grew a [?] todo invite: " + t.text);
ok(hasPair("[post]", "W", "O", "//PIN-1/: post 'PIN-1: pin sample ticket'"),
   "PIN-1 [post] lacks green W + O `//PIN-1/: post '<ticket title>'`");
ok(hasPair("[-1]", "A", "O", "//PIN-1/: get"),
   "PIN-1 behind button lacks salmon A `[-1]` + O `//PIN-1/: get`");
ok(hasPair("[+1]", "G", "O", "//BR-2/: post"),
   "BR-2 ahead button lacks salad G `[+1]` + O `//BR-2/: post`");
ok(hasPair("[done]", null, "O", "//PIN-1/: done ."),
   "PIN-1 [done] lacks O `//PIN-1/: done .`");
ok(hasPair("[dont]", null, "O", "//PIN-1/: dont ."),
   "PIN-1 [dont] lacks O `//PIN-1/: dont .`");
ok(hasPair("[done]", null, "O", "//FOR-4/: done ."),
   "FOR-4 [done] lacks O `//FOR-4/: done .`");
//  [get] is gone everywhere; FOR-4 has no ticket page -> NO commit [post]; a wt
//  in sync (TRK-5) shows NO ahbeh button; the [rm -rf] spell stays retired.
for (const t of toks) {
  if (t.tag !== "O") continue;
  if (t.text.indexOf(": get ///") >= 0)
    fail("a retired [get] `get ///` spell survived: " + t.text);
  if (t.text.indexOf("//FOR-4/: post '") === 0)
    fail("a page-less wt grew a commit [post] spell: " + t.text);
  if (t.text.indexOf("//TRK-5/: get") === 0 || t.text.indexOf("//TRK-5/: post") === 0)
    fail("an in-sync wt grew an ahbeh button: " + t.text);
  if (t.text.indexOf("rm ") >= 0) fail("a retired rm spell survived: " + t.text);
}

//  --- button placement: [?] then [±] FIRST, then the rest ------------------
//  WORK-010 RULING: [?] and [±] are the FIRST TWO buttons (that order), ahead
//  of the run; then [post], the ahbeh, [done]/[dont].
const iKey  = idxOf("//PIN-1", "U", "status //PIN-1");
const iHelp = idxOf("[?]", "O", "//: todo PIN-1");
const iDiff = idxOf("[±]", "U", "diff //PIN-1");
const iPost = idxOf("[post]", "O", "//PIN-1/: post 'PIN-1: pin sample ticket'");
const iBeh  = idxOf("[-1]", "O", "//PIN-1/: get");
const iDone = idxOf("[done]", "O", "//PIN-1/: done .");
const iDont = idxOf("[dont]", "O", "//PIN-1/: dont .");
ok(iKey >= 0 && iHelp > iKey && iDiff > iHelp && iPost > iDiff && iBeh > iPost &&
   iDone > iBeh && iDont > iDone,
   "PIN-1 button order is not key<[?]<[±]<[post]<[-1]<…<[done]<[dont]");
//  Between the key and [?]: only the dotted leader / spacers (r2 filler).
for (let i = iKey + 2; i < iHelp; i++)
  ok(/^[ ┄]+$/.test(toks[i].text),
     "non-filler between the key and [?]: '" + toks[i].text + "'");

//  --- r2: NAME-only bold, one dotted leader per row, aligned columns --------
//  Every C (bold) token is exactly a repo NAME — never a date/hash/msg tail.
const NAMES = { meta: 1, "vend/ext": 1, deep: 1 };
for (const t of toks)
  if (t.tag === "C" && !NAMES[t.text])
    fail("a non-name token rides the bold C tag: '" + t.text + "'");
ok(visible.indexOf("//PIN-1 ┄") >= 0, "the //PIN-1 row lacks its dotted leader");
//  Alignment: [±] and the #hashlet sit at ONE visible column on EVERY row
//  that has them (KEYW + fixed button slots — chars, not bytes).  The absent
//  [?] slot ┄-pads to the SAME width, so [±] holds its column either way.
{
  let diffCol = -1, hashCol = -1;
  for (const s of visible.split("\n")) {
    const di = s.indexOf("[±]");
    if (di >= 0) {
      const col = Array.from(s.slice(0, di)).length;
      if (diffCol < 0) diffCol = col;
      else if (col !== diffCol) fail("[±] column drifts: " + col + " vs " + diffCol);
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

//  --- WORK-006: the grid closes up with ┄ leaders --------------------------
//  Absent button slots ┄-fill (not blanks) and short subjects ┄-pad to 30, so
//  [done]/[dont] land at ONE column on every wt row.
function wtLine(key) {
  for (const s of visible.split("\n")) if (s.indexOf(key + " ") >= 0) return s;
  return "";
}
//  A title-less row (FOR-4: no ticket page → absent [post]) and an in-sync row
//  (TRK-5: zero ahbeh) carry a ┄ leader AFTER [±], never a blank gap.  Both
//  are also non-ticket wts, so the leading [?] slot ┄-pads before [±] too.
for (const key of ["//FOR-4", "//TRK-5"]) {
  const s = wtLine(key), di = s.indexOf("[±]");
  ok(di >= 0 && s.slice(di + 3).indexOf("┄") >= 0,
     key + " row has a blank (not ┄) button/ahbeh gap after [±]");
  const hi = s.indexOf("[±]"), ki = s.indexOf(key);
  ok(ki >= 0 && hi > ki && s.slice(ki + key.length, hi).indexOf("┄") >= 0,
     key + " (non-ticket) lacks a ┄-padded absent [?] slot before [±]");
}
//  [done] lands at ONE visible column on EVERY wt row (short subjects ┄-pad).
{
  let doneCol = -1, seen = 0;
  for (const s of visible.split("\n")) {
    const d = s.indexOf("[done]");
    if (d < 0) continue;
    seen++;
    const col = Array.from(s.slice(0, d)).length;
    if (doneCol < 0) doneCol = col;
    else if (col !== doneCol) fail("[done] column drifts: " + col + " vs " + doneCol);
  }
  ok(seen >= 3, "expected [done] on several wt rows, saw " + seen);
}

//  --- WORK-016: the leader run is CONTINUOUS -------------------------------
//  Between two cells: ONE uninterrupted ┄ run with exactly one space of
//  breathing at each end — no blank seam splitting two fills, no double blank
//  where a slot is absent, no ┄ abutting a button face.
for (const s of visible.split("\n")) {
  if (s.indexOf("┄") < 0) continue;
  const g = s.replace(/^[│ ]*[├└]?[─┄]* ?/, "");   // past the tree rails
  ok(!/┄ +┄/.test(g), "a blank seam splits the leader run: '" + s + "'");
  ok(!/ {2}/.test(g), "a double blank in the leader grid: '" + s + "'");
  ok(!/┄\[|\]┄/.test(g), "a button abuts the leader, no breathing space: '" + s + "'");
}
//  A repo row (`meta`, no buttons) ┄-FILLS its whole button region: one run
//  from the name all the way to the ahbeh/date column, never blanked.
ok(/^meta ┄{40,} /.test(wtLine("meta")),
   "the meta repo row blanks its button region: '" + wtLine("meta") + "'");

//  --- the ahbeh buttons: behind '[-N]' salmon 'A', ahead '[+N]' salad 'G' ----
function hasTagged(tag, text) {
  for (const t of toks) if (t.tag === tag && t.text === text) return true;
  return false;
}
ok(hasTagged("A", "[-1]"), "PIN-1's behind button lacks the salmon 'A' span");
ok(hasTagged("G", "[+1]"), "BR-2's ahead button lacks the salad 'G' span");

//  --- WORK-005: the age fade — each wt row carries a leading bare `#rrggbb` O
//  (the row's default-fg), darkening by the day: fresh #000000, 3-day #444444,
//  week+ #888888.  run.sh ages ext one 8.5d (PIN-1) and ext two 3.5d (TRK-5);
//  DET-3/FOR-4 stay fresh.  The marker is the O right before the row's `//KEY`.
function rowFade(key) {
  let ki = -1;
  for (let i = 0; i < toks.length; i++)
    if (toks[i].tag === "S" && toks[i].text === "//" + key) { ki = i; break; }
  for (let i = ki; i >= 0; i--)
    if (toks[i].tag === "O")
      return /^#[0-9a-f]{6}$/.test(toks[i].text) ? toks[i].text : null;
  return null;
}
ok(rowFade("DET-3") === "#000000",
   "fresh DET-3 row lacks the black #000000 fade, got " + rowFade("DET-3"));
ok(rowFade("TRK-5") === "#444444",
   "3-day TRK-5 row lacks the #444444 fade, got " + rowFade("TRK-5"));
ok(rowFade("PIN-1") === "#888888",
   "8+day PIN-1 row lacks the #888888 fade, got " + rowFade("PIN-1"));
//  The fade is INVISIBLE in plain (an O token, hidden) — visible text unchanged.
ok(visible.indexOf("#000000") < 0 && visible.indexOf("#888888") < 0,
   "an age-fade marker leaked into visible text");

//  Through the REAL pager colour paint (emitBody -> paintWhyRow): the PIN-1 row
//  emits the truecolor grey SGR `38;2;136;136;136` (#888888) on its default cells.
function paintFind(key) {
  for (const h of hunks) {
    const hk = { text: h.text, toks: h.toks || new Uint32Array(0) };
    for (const r of bro.indexRows(hk, 500, false)) {
      const s = pager.paintRow(hk, r.off, r.end, true, r.pass);
      if (s.indexOf("//" + key) >= 0) return s;
    }
  }
  return "";
}
ok(paintFind("PIN-1").indexOf("38;2;136;136;136") >= 0,
   "the real pager did not paint PIN-1 with the #888888 truecolor fg");
ok(paintFind("TRK-5").indexOf("38;2;68;68;68") >= 0,
   "the real pager did not paint TRK-5 with the #444444 truecolor fg");

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
//  clickAct(spell, ctx): press the cell resolving to `spell`, assert the LAST
//  _actSpell was (verb-args, ctx) — the mutation ran in the ROW's own context.
function clickAct(label, spell, wantSpell, ctx) {
  const cell = cellOf(spell);
  ok(cell, "no clickable " + label + " cell resolves to `" + spell + "`");
  click(cell);
  const a = acts[acts.length - 1] || [];
  ok(a[0] === wantSpell && a[1] === ctx,
     "the " + label + " click must _actSpell(`" + wantSpell + "`, `" + ctx +
     "`), got " + JSON.stringify(a));
}
//  WORK-004: the ahbeh buttons mint BARE post/get in the row ctx; [post] the
//  titled commit; [done] the move+mark — all anchored on the row, not the pager.
clickAct("[-N] behind", "//PIN-1/: get", "get", "//PIN-1");
clickAct("[+N] ahead", "//BR-2/: post", "post", "//BR-2");
clickAct("[post] commit", "//PIN-1/: post 'PIN-1: pin sample ticket'",
         "post 'PIN-1: pin sample ticket'", "//PIN-1");
clickAct("[done]", "//PIN-1/: done .", "done .", "//PIN-1");
const navCell = cellOf("status //BR-2");
ok(navCell, "no clickable cell resolves to `status //BR-2`");
click(navCell);
ok(runs.length === 1 && runs[0][0] === "status //BR-2" && runs[0][1] === undefined,
   "the key click must _runSpell(`status //BR-2`) context-less, got " + JSON.stringify(runs));
//  WORK-010: [±] and [?] are NAV clicks (non-mutation → _runSpell), context-less.
//  The cell resolves to the raw token; the dispatch parseOspell-splits it, so the
//  [?] O-invite `//: todo KEY` drives the verb `todo KEY` in the EMPTY context.
function clickRun(label, cellTok, wantSpell) {
  const cell = cellOf(cellTok);
  ok(cell, "no clickable " + label + " cell resolves to `" + cellTok + "`");
  click(cell);
  const r = runs[runs.length - 1] || [];
  ok(r[0] === wantSpell && r[1] === undefined,
     "the " + label + " click must _runSpell(`" + wantSpell + "`) context-less, got " +
     JSON.stringify(r));
}
clickRun("[±] diff", "diff //PIN-1", "diff //PIN-1");
clickRun("[?] ticket", "//: todo PIN-1", "todo PIN-1");
clickRun("[?] topic", "//: todo PIN", "todo PIN");
tty.size = realSize;

io.log("test/work/view OK (" + toks.length + " tokens)\n");
