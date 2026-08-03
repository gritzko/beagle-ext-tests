//  test/todo/rows/check.js — TODO-005: THE `:todo` ROW GREW TWO BUTTON FRAMES.
//
//  The board row was a bare `KEY <elastic title> [done]`.  It now carries, in
//  order: the severity bullet, the key, [/todo/TODO/TODO-004]'s inline filter
//  brackets, the KEYW dotted leader and — on a row whose ticket owns a
//  `work/<KEY>*` worktree — the two FIXED-width button frames, then the title:
//
//    ● TIC-002 ┄┄┄ [ i 14  1  2  ✓] [ ≡  2   ] <title> [done]
//
//  Every button is 2 CELLS of COLOURED FOREGROUND on the default background —
//  over a very pale wash of that tone — with a face of 2 cells; the
//  count face is 2 cells — sigil+digit under ten, bare 2 digits above.  FILE frame (16
//  cols): the ` i` status button, the three staging counts (changed → `put`,
//  gone → `delete`, untracked → `put +`) and the ` ✓` commit.  Each count slot
//  is THREE-STATE — unstaged rows light the button, a wholly-staged class keeps
//  its CLASS COLOUR but sheds wash+spell (info, no grey — 2026-08-03 ruling),
//  an empty class blanks.  COMMIT frame
//  (10 cols): the ` ≡` log button plus TWO FIXED sub-slots — POST position then
//  GET position, so a behind count never drifts into the post column — with a
//  DIVERGED `A⇄B` as ONE patch button across both.
//  Rulings pinned here: a frame DELIMITS its own columns, so nothing inside the
//  brackets is ┄-filled (empty slots are plain SPACES) and the dotted leader
//  runs straight THROUGH the frames region on a wt-LESS row, so every title in
//  the hunk lands at ONE column.  A LIVE button's O opens `#<pale><tone> ` —
//  both slots of the WHY-001 colour prefix, the wash DERIVED from the tone by
//  the one theme.pale() — and the WHOLE face is the click zone; a grey or blank
//  slot carries no O at all.  The face rides its LEGACY 16-palette tag, which
//  the O overrides, so a lost prefix degrades to the class colour, never grey.
//
//  RED before the change: no bullet, no frames, no wash prefix, no rails, no
//  head scan (the ONE read gave the title only, so `Sub:` was unreadable).
//  GREEN after — the cases below.
//
//  The bullet's COLOUR indexes the row's `prio`, which is TODO-004's prioOf
//  (`Sev:` off the meta index, the legacy header mark as the fallback) — its
//  own case owns the pair reading, so this one drives `prio` directly and pins
//  what the ROW does with it, plus the mark-fallback order the index-less path
//  still answers.
//
//  Pure JS unit case (no worktree, no store) — this script plants its own
//  fixture board + work/ under $TMP.  Registered by the be/test glob as
//  be-js-todo-rows.
"use strict";

const { eq, ok } = require("../../lib/assert.js");
//  DIS-054 isolated-clone require: derive the be/ code dir from this script's
//  own path (`<be>/test/todo/rows/check.js` → `<be>`).
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const todo = _req("views/todo/todo.js");
//  colours are THEME data, so the expectations DERIVE them (one source) — the
//  literal pin of the pale factor is its own case below.
const theme = _req("view/theme.js");
function paint(name) { return theme.pale(theme.BTN[name]) + theme.BTN[name]; }
//  the same pair as `slot()` reports it (the O prefix, tagged).
function btnOf(name) { return "btn:" + paint(name); }

//  --- the fixture tree --------------------------------------------------------
const TMP = io.getenv("TMP") || "/tmp";
const root = TMP + "/todo005-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
function mkdirp(p) {
  let acc = "";
  for (const s of p.split("/")) { if (s === "") { acc = ""; continue; } acc += "/" + s;
    try { io.mkdir(acc); } catch (e) {} }
}
function plant(abs, body) {
  mkdirp(abs.slice(0, abs.lastIndexOf("/")));
  const u = utf8.Encode(body);
  const b = io.buf(u.length + 8); b.feed(u);
  const fd = io.open(abs, "c"); io.writeAll(fd, b); io.close(fd);
}

const BOARD = root + "/todo", WORK = root + "/work";
//  TIC: the order / wt topic.  Numbering runs AGAINST the priority order so a
//  numeric sort cannot pass for a priority one.
function tic(n, head, meta) { plant(BOARD + "/TIC/TIC-" + n + ".mkd", head + meta + "\nbody\n"); }
tic("001", "#   TIC-001: unmarked, reads MED\n", "Now: OPEN\n");
tic("002", "#   TIC-002 [CRIT]: sorts first\n", "Sev: CRIT\nNow: OPEN\n");
tic("003", "#   TIC-003 [LOW]: sorts last\n", "Sev: LOW\nNow: OPEN\n");
tic("004", "#   TIC-004 [HIGH]: sorts second\n", "Sev: HIGH\nNow: OPEN\n");
//  A `Sev:` line NOT directly under the header (a body line) must NOT count.
tic("005", "#   TIC-005: the pair run stops at the first non-pair line\n",
    "Now: OPEN\n\nSev: CRIT\n");
tic("006", "#   TIC-006 [DONE]: closed by the legacy mark\n", "Now: DONE\n");
//  TODO-005 [go]: a wt-LESS ticket carrying `Rep:` — the repo it relates to, a
//  (usually relative) repo URI — is the ONE creating action on the board.
tic("007", "#   TIC-007: carries Rep:, offers the mint button\n", "Now: OPEN\nRep: ///be\n");

//  FAM: the `Sub:` family topic — one parent, two kids, one grandkid, one
//  cross-topic Sub:, one closed-parent Sub:, and a two-node CYCLE.  The closed
//  parent reads closed through the LEGACY mark (there is no store here).
function fam(n, head, meta) { plant(BOARD + "/FAM/FAM-" + n + ".mkd",
  "#   FAM-" + n + head + "\n" + meta + "\nbody\n"); }
fam("001", ": the parent", "Now: OPEN\n");
fam("002", ": child a", "Now: OPEN\nSub: FAM-001\n");
fam("003", ": child b", "Now: OPEN\nSub: FAM-001\n");
fam("004", ": grandchild of 002", "Now: OPEN\nSub: FAM-002\n");
fam("005", ": cross-topic Sub renders flat", "Now: OPEN\nSub: TIC-001\n");
fam("006", ": closed-parent Sub renders flat", "Now: OPEN\nSub: FAM-009\n");
fam("007", ": cycle with 008", "Now: OPEN\nSub: FAM-008\n");
fam("008", ": cycle with 007", "Now: OPEN\nSub: FAM-007\n");
fam("009", " [DONE]: the closed parent", "Now: DONE\n");


//  The fixture work/ tree: BE-044 gate — a wt is a dir owning a `.be` FILE.
function wt(name) { plant(WORK + "/" + name + "/.be", "fixture\n"); }
wt("TIC-002");            // an exact-name wt
wt("TIC-004-adv");        // WORK-010 suffix tolerance: `TIC-004-adv` → TIC-004
wt("TIC-001b");           // a letter-run suffix
wt("TIC-001c");           // …and a SECOND: the name-sorted first wins the slot
wt("README");             // not a ticket name — never matches
plant(WORK + "/nogate/x", "no .be file, never lists\n");

//  --- the ambient board -------------------------------------------------------
globalThis.be = globalThis.be || {};
be.todoRoot = function () { return BOARD; };
be.workRoot = function () { return WORK; };
be.projectRoot = function () { return root; };
be.now = 0n;
//  The count cells cost a tree open; COUNT the opens so "only a wt-having
//  ticket pays" and "the no-wt board opens nothing" are assertions, not hopes.
let treeAts = [];
be.treeAt = function (d) { treeAts.push(d); throw "no store in this fixture"; };

//  --- the hunk reader ---------------------------------------------------------
function tagOf(w) { return String.fromCharCode(65 + ((w >>> 27) & 0x1f)); }
function endOf(w) { return w & 0xffffff; }
function render(groups, headers, btns) {
  treeAts = [];
  const fed = [];
  const sink = { feed: function (b, body, toks) { fed.push({ body: body, toks: toks }); } };
  todo.runReset();
  try { todo.emitList(sink, "todo", groups, headers, btns); }
  finally { todo.runClose(); }
  eq(fed.length, 1, "one hunk fed");
  const body = fed[0].body, toks = fed[0].toks;
  //  cells = [{ tag, text }] in emit order; lines = the VISIBLE text (O dropped).
  const cells = [];
  let prev = 0, vis = "";
  for (let i = 0; i < toks.length; i++) {
    const end = endOf(toks[i]), tag = tagOf(toks[i]);
    const text = utf8.Decode(body.slice(prev, end));
    cells.push({ tag: tag, text: text });
    if (tag !== "O") vis += text;
    prev = end;
  }
  return { cells: cells, lines: vis.split("\n") };
}
//  The cell run of the row carrying `key` as its `F` token.
function rowCells(r, key) {
  let cur = [];
  for (const c of r.cells) {
    cur.push(c);
    if (c.tag !== "O" && c.text.indexOf("\n") >= 0) {
      for (const x of cur) if (x.tag === "F" && x.text === key) return cur;
      cur = [];
    }
  }
  return [];
}
function lineOf(r, key) {
  for (const l of r.lines) if (l.indexOf(key) >= 0) return l;
  return "";
}
//  The char column at which the row's elastic `B` title opens.
function titleCol(r, key) {
  const l = lineOf(r, key);
  const t = rowCells(r, key).filter(function (c) { return c.tag === "B"; })[0];
  return Array.from(l.slice(0, l.indexOf(t.text))).length;
}
function tags(r, key, n) {
  return rowCells(r, key).map(function (c) { return c.tag; }).join("").slice(0, n);
}
function group(tickets) { return { topic: "TIC", tickets: tickets }; }

//  --- 1. the ONE head read: title + the raw pairs under it ---------------------
const h5 = todo.pageHead(BOARD + "/TIC/TIC-005.mkd");
eq(h5.title, "TIC-005: the pair run stops at the first non-pair line", "1: the title reads");
eq(h5.meta.Now, "OPEN", "1: a pair directly under the header parses");
eq(h5.meta.Sev, undefined, "1: the run STOPS at the first non-pair line");
eq(todo.pageHead(BOARD + "/FAM/FAM-002.mkd").meta.Sub, "FAM-001",
   "1: `Sub:` — the pair no packed index row gives back — reads verbatim");

//  --- 2. the ORDER: priority first, then number (the mark-fallback path) -------
const tics = todo.listTopics(BOARD).filter(function (g) { return g.topic === "TIC"; })[0];
eq(tics.tickets.map(function (t) { return t.key; }).join(","),
   "TIC-002,TIC-004,TIC-001,TIC-005,TIC-007,TIC-003",
   "2: CRIT > HIGH > MED/none > LOW, then numeric — a closed ticket never lists");

//  --- 3. the PLAIN row is chrome-free -----------------------------------------
const plain = render([tics], false, false);
eq(lineOf(plain, "TIC-002"), "TIC-002 [CRIT]: sorts first", "3: plain row is the header line");
const ptxt = plain.lines.join("");
ok(ptxt.indexOf("●") < 0 && ptxt.indexOf("○") < 0, "3: no bullet in plain");
ok(ptxt.indexOf("[ i") < 0 && ptxt.indexOf("≡") < 0, "3: no button frames in plain");
ok(ptxt.indexOf("┄") < 0, "3: no column fill in plain");
eq(treeAts.length, 0, "3: plain opens no tree");

//  --- 4. the PAGER row: bullet FIRST, then key, wt link, counts, title ---------
//  The bullet's colour indexes `prio` (TODO-004's `Sev:`-then-mark reading);
//  the rows are driven directly here so every palette slot is covered.
const bullets = render([group([
  { key: "TIC-002", title: "TIC-002: crit", prio: 0 },
  { key: "TIC-004", title: "TIC-004: high", prio: 1 },
  { key: "TIC-001", title: "TIC-001: med",  prio: 2 },
  { key: "TIC-003", title: "TIC-003: low",  prio: 3 },
  { key: "TIC-006", title: "TIC-006: done", prio: 2, closed: true },
])], false, true);
function bullet(key) { const c = rowCells(bullets, key)[0]; return c.text + c.tag; }
eq(bullet("TIC-002"), "●M", "4: CRIT is a red solid bullet");
eq(bullet("TIC-004"), "●A", "4: HIGH is a salmon solid bullet");
eq(bullet("TIC-001"), "●S", "4: MED/none is a plain solid bullet");
eq(bullet("TIC-003"), "●D", "4: LOW is a dim solid bullet");
eq(bullet("TIC-006"), "○D", "4: a CLOSED ticket, when shown, is a HOLLOW bullet");

const pg = render([tics], false, true);
//  4b. the cell ORDER of a wt-having row: the bullet run, then the FILE frame
//  (bracket, the ` i` face on a THEME-NEUTRAL tag, its colour-bearing O, ...).
eq(tags(pg, "TIC-002", 9), "MSFOSSDVO",
   "4b: bullet, sep, key, nav-O, leader, sep, `[`, the face on its fallback tag, its O");
//  4c. the row's spells, in emit order.  The wt here is UNREADABLE (no store in
//  the fixture), so only the two NAV buttons light — the four action slots have
//  no counts to act on and mint nothing.
const sp = rowCells(pg, "TIC-002").filter(function (c) { return c.tag === "O"; })
                                  .map(function (c) { return c.text; });
eq(sp[0], "todo TIC-002", "4c: the key mints the context-less todo nav");
eq(sp[1], paint("status") + " status //TIC-002",
   "4c: ` i` mints the wt status behind its pale+tone pair, empty context");
eq(sp[2], paint("log") + " log //TIC-002", "4c: ` ≡` mints the wt log");
//  the trailing panel is the LAST pair of spells on every row.
eq(sp[sp.length - 2], paint("done") + " done TIC-002", "4c: the panel's ✓ mints `done KEY`");
eq(sp[sp.length - 1], paint("dont") + " dont TIC-002", "4c: … and its ✗ mints `dont KEY`");

//  --- 5. the wt MATCH rule ------------------------------------------------------
const ix = todo.wtIndex();
eq(ix.get("TIC-002").name, "TIC-002", "5: an exact wt name matches");
eq(ix.get("TIC-004").name, "TIC-004-adv", "5: a `-word` suffix still matches");
eq(ix.get("TIC-001").name, "TIC-001b", "5: two wts — the name-sorted FIRST wins");
eq(ix.get("TIC-003"), undefined, "5: a ticket with no wt gets no slot");
eq(ix.size, 3, "5: README / a `.be`-less dir are not worktrees");
//  5b. RULING: the frames hang off a wt, and a wt-LESS row ┄-fills the WHOLE
//  frames region instead — so every title in the hunk lands at ONE column again.
ok(lineOf(pg, "TIC-002").indexOf("[ i") > 0, "5b: a wt-having row opens the FILE frame");
ok(lineOf(pg, "TIC-002").indexOf("[ ≡") > 0, "5b: … and the COMMIT frame");
ok(lineOf(pg, "TIC-003").indexOf("[ i") < 0 && lineOf(pg, "TIC-003").indexOf("≡") < 0,
   "5b: a wt-less row grows neither frame");
eq(todo.FRAMEW.region, todo.FRAMEW.file + todo.FRAMEW.commit + 2,
   "5b: the region IS the two frames plus the space that leads each");
eq(titleCol(pg, "TIC-003"), titleCol(pg, "TIC-002"),
   "5b: … so a wt-less title lands at the SAME column as a wt-having one");
eq(titleCol(pg, "TIC-005"), titleCol(pg, "TIC-004"), "5b: … on every row of the list");
//  the ┄ leader runs straight through: one uninterrupted run, no blank seam.
ok(/┄{20}/.test(lineOf(pg, "TIC-003")), "5b: the wt-less row's leader is ONE ┄ run");

//  --- 6. counts ONLY behind the wt check ---------------------------------------
//  Three listed tickets have a wt, so exactly three trees are opened; the
//  fixture has no store, so each read fails and the slots ┄-fill — no error row.
eq(treeAts.length, 3, "6: one tree open per wt-HAVING ticket, none for the rest");
eq(pg.lines.length, tics.tickets.length + 1, "6: an unreadable wt adds no row");
ok(lineOf(pg, "TIC-002").indexOf("[ i            ] [ ≡      ]") > 0,
   "6: an UNREADABLE wt lights the two nav buttons and BLANKS every action slot");
//  6b. a board with NO matching wt opens NOTHING.
const fams = todo.listTopics(BOARD).filter(function (g) { return g.topic === "FAM"; })[0];
const fpg = render([fams], false, true);
eq(treeAts.length, 0, "6b: the no-wt board opens no tree at all");

//  --- 6c. the FILE frame itself ------------------------------------------------
//  Driven directly, so every state of the three-state rule is covered without a
//  store.  `parts` and `spans` are 1:1 (one span() call each), so a frame reads
//  back as cells; an `O` cell is a button's colour+spell, everything else is
//  the visible face.
function frameOf(fn, stat) {
  const parts = [], spans = [];
  todo[fn](parts, spans, 0, { key: "TIC-002", title: "TIC-002: crit",
                              wt: { name: "TIC-002" }, stat: stat });
  const cells = [], sp = [];
  let vis = "";
  for (let i = 0; i < parts.length; i++) {
    const c = { tag: String.fromCharCode(65 + spans[i][0]), text: utf8.Decode(parts[i]) };
    cells.push(c);
    if (c.tag === "O") sp.push(c.text); else vis += c.text;
  }
  return { text: vis, w: Array.from(vis).length, cells: cells, spells: sp };
}
//  A slot's state, read off the face: `btn:<pale><tone>` when an O carries its
//  colours, `grey` when the face rides the dim tag with no O, `?` when there is
//  no such face.  This is the whole three-state rule in one probe.
function slot(f, face) {
  for (let i = 0; i < f.cells.length; i++)
    if (f.cells[i].tag !== "O" && f.cells[i].text === face) {
      const nx = f.cells[i + 1];
      //  an O opening `##` is the fg-only INFO form (coloured, spell-less);
      //  a full `#<bg>#<fg>` pair is a live button.
      if (nx && nx.tag === "O")
        return (nx.text[1] === "#" ? "info:" : "btn:") + nx.text.slice(0, 14);
      return f.cells[i].tag === "D" ? "grey" : "plain";
    }
  return "?";
}
const ZERO = { chg: 0, add: 0, del: 0 };
function stat(un, st, counts, patch) {
  const u = Object.assign({}, ZERO, un || {}), s = Object.assign({}, ZERO, st || {});
  return { un: u, st: s, staged: s.chg + s.add + s.del,
           dirty: (u.chg + u.add + u.del) > 0, counts: counts || null,
           patch: patch === undefined ? "?main" : patch };
}
const fNull = frameOf("fileFrame", null);
eq(fNull.text, "[ i            ]", "6c: no stat ⇒ the ` i` button and four BLANK slots");
eq(fNull.w, todo.FRAMEW.file, "6c: … 16 columns");
eq(fNull.spells.length, 1, "6c: … and ONLY the status button clicks");
ok(fNull.text.indexOf("┄") < 0, "6c: NOTHING inside the brackets is ┄-filled");
eq(frameOf("fileFrame", stat()).text, fNull.text, "6c: a fully CLEAN wt reads the same");
//  UNSTAGED rows light every slot they fill; the ✓ is BLANK (nothing staged
//  yet — no grey ✓, the 2026-08-03 no-grey ruling).
const fUn = frameOf("fileFrame", stat({ chg: 14, add: 2, del: 1 }));
eq(fUn.text, "[ i 14 -1 +2   ]", "6c: 2-cell faces — bare `14`, sigil+digit `-1`/`+2`");
eq(fUn.w, todo.FRAMEW.file, "6c: … still 16 columns");
eq(slot(fUn, "14"), btnOf("chg"), "6c: changed rides the file trio's blue and clicks");
eq(slot(fUn, "-1"), btnOf("del"), "6c: deleted rides its red rotation and clicks");
eq(slot(fUn, "+2"), btnOf("add"), "6c: new rides its green rotation and clicks");
eq(slot(fUn, " ✓"), "?", "6c: NO ✓ face at all while nothing is staged");
eq(fUn.spells.join("|"),
   [paint("status") + " status //TIC-002", paint("chg") + " //TIC-002/: put",
    paint("del") + " //TIC-002/: delete", paint("add") + " //TIC-002/: put +"].join("|"),
   "6c: the three staging spells, each behind its fg colour, in the wt's ctx");
//  STAGED-only: the class KEEPS its colour but sheds the wash and the spell
//  (INFO, not a button — the 2026-08-03 no-grey ruling); ✓ lights.
const fSt = frameOf("fileFrame", stat(null, { chg: 2 }));
eq(fSt.text, "[ i ~2        ✓]", "6c: a wholly-staged class shows its STAGED count");
eq(slot(fSt, "~2"), "info:#" + theme.BTN.chg + " ",
   "6c: … class-coloured INFO — fg-only O, no wash, nothing left to stage");
eq(slot(fSt, " ✓"), btnOf("ci"), "6c: … and the ✓ lights green");
eq(fSt.spells[fSt.spells.length - 1],
   paint("ci") + " //TIC-002/: post 'TIC-002: crit'",
   "6c: … minting the WORK-008 `KEY: <bare title>` commit message");
//  A class dirty on BOTH axes still lights (the unstaged count wins).
const fBoth = frameOf("fileFrame", stat({ chg: 3 }, { chg: 9 }));
eq(fBoth.text, "[ i ~3        ✓]", "6c: unstaged>0 wins — the UNSTAGED count shows");
eq(slot(fBoth, "~3"), btnOf("chg"), "6c: … lit and clickable");
eq(frameOf("fileFrame", stat({ chg: 900, add: 900, del: 900 })).text,
   "[ i 99 99 99   ]", "6c: two-digit clamp — at 99 the sigil gives way to the digits");

//  --- 6d. the COMMIT frame: fixed post/get positions ---------------------------
function mode(counts, patch) { return frameOf("commitFrame", stat(null, null, counts, patch)); }
const mNone = frameOf("commitFrame", null);
eq(mNone.text, "[ ≡      ]", "6d: no counts ⇒ both sub-slots blank");
eq(mNone.w, todo.FRAMEW.commit, "6d: … 10 columns");
eq(mNone.spells.length, 1, "6d: … only the ` ≡` log button clicks");
eq(mode({ ahead: 0, behind: 0 }).text, "[ ≡      ]", "6d: in step ⇒ the same");
const mA = mode({ ahead: 2, behind: 0 });
eq(mA.text, "[ ≡ +2   ]", "6d: ahead-only fills the POST position, blanks the GET one");
eq(mA.w, todo.FRAMEW.commit, "6d: … 10 columns");
eq(slot(mA, "+2"), btnOf("post"), "6d: … the commit trio's green, and it clicks");
eq(mA.spells[1], paint("post") + " //TIC-002/: post", "6d: … minting bare post");
const mB = mode({ ahead: 0, behind: 13 });
eq(mB.text, "[ ≡    13]", "6d: behind-only fills the GET position — it never drifts left");
eq(slot(mB, "13"), btnOf("get"), "6d: … the commit trio's red, and it clicks");
eq(mB.spells[1], paint("get") + " //TIC-002/: get", "6d: … minting bare get");
const mD = mode({ ahead: 2, behind: 13 });
eq(mD.text, "[ ≡  2⇄13]", "6d: DIVERGED is ONE `A⇄B` button over both sub-slots");
eq(mD.w, todo.FRAMEW.commit, "6d: … still 10 columns");
eq(mode({ ahead: 12, behind: 34 }).text, "[ ≡ 12⇄34]", "6d: `12⇄34` fills the 5 cells exactly");
eq(slot(mD, " 2⇄13"), btnOf("patch"), "6d: … Pantone Diode Blue, the commit trio's own");
eq(mD.spells[1], paint("patch") + " //TIC-002/: patch '?main'",
   "6d: … minting patch against the wt's OWN attached branch");
eq(mode({ ahead: 900, behind: 900 }).text, "[ ≡ 99⇄99]", "6d: each side clamps at 2 digits");
//  RULING: the patch must reach a uriTrack / trunk wt too.  `#<hashlet>` is NOT
//  the form — patchscope reads a fragment as the NAMED scope (a CHERRY-PICK,
//  fork = parent), not the LINE absorb `?branch` does.  The LINE forms are the
//  TRACK ADDRESS (PATCH-010 TREE source: theirs = that wt's cur tip, fork = LCA)
//  and BARE `patch` (PATCH-015: the whole missing line of the tracked ref).
const mT = mode({ ahead: 2, behind: 13 }, "//BE-001/");
eq(mT.spells[1], paint("patch") + " //TIC-002/: patch '//BE-001/'",
   "6d: a uriTrack wt patches its TRACK ADDRESS — the same tip ahbeh measured");
const mBare = mode({ ahead: 2, behind: 13 }, "");
eq(mBare.spells[1], paint("patch") + " //TIC-002/: patch",
   "6d: a trunk wt patches BARE — the whole missing line of the tracked ref");
const mDb = mode({ ahead: 2, behind: 13 }, null);
eq(mDb.text, "[ ≡  2⇄13]", "6d: a wt no patch form reaches still SHOWS the pair");
eq(slot(mDb, " 2⇄13"), "grey", "6d: … grey and dead");
eq(mDb.spells.length, 1, "6d: … so only the log button clicks");

//  --- 6e. every LIVE button is its tone over a PALE wash of that tone ---------
//  Its `O` opens `#<pale><tone> ` — BOTH slots of the WHY-001 colour prefix
//  (view/bro.js whyBgAt) — so one token spells the button's whole look and its
//  click, and the tag space (full at 32 codes) needs no new slot.  The wash is
//  DERIVED by the one theme.pale(), never hand-picked, and the face is ALWAYS 2
//  cells (or the 5-cell diverged pair): the whole visible button is painted and
//  the whole visible button clicks.
eq(theme.pale("#0085ca"), "#e0f0f9", "6e: pale() mixes the tone toward white by BTN_PALE");
eq(theme.BTN_PALE > 0.5 && theme.BTN_PALE < 1, true, "6e: … one tunable factor, in (0.5,1)");
eq(theme.pale("#ffffff"), "#ffffff", "6e: … white is its own pale");
for (const f of [fNull, fUn, fSt, fBoth, mA, mB, mD, mT, mBare, mDb])
  for (let i = 0; i < f.cells.length; i++) {
    const c = f.cells[i];
    if (c.tag !== "O") continue;
    //  fg-only `##rrggbb ` = a staged-count INFO span: coloured, wash-less,
    //  and its shed spell is EMPTY (a click falls through to the row).
    const info = /^#(#[0-9a-f]{6}) $/.exec(c.text);
    if (info) {
      const fw0 = Array.from(f.cells[i - 1].text).length;
      eq(fw0, 2, "6e: an info span is a whole 2-cell count face");
      ok(f.cells[i - 1].tag !== "D" && f.cells[i - 1].tag !== "S",
         "6e: … riding a LEGACY colour tag, never grey");
      continue;
    }
    const m = /^(#[0-9a-f]{6})(#[0-9a-f]{6}) \S/.exec(c.text);
    ok(!!m, "6e: a button's O opens with the `#<bg><fg>` pair (" + c.text + ")");
    eq(m[1], theme.pale(m[2]), "6e: … and the bg IS pale(fg), from the ONE derivation");
    const fw = Array.from(f.cells[i - 1].text).length;
    eq(fw === 2 || fw === 5, true,
       "6e: … and the face it paints is a whole 2-cell button (5 for the pair)");
    ok(f.cells[i - 1].tag !== "D" && f.cells[i - 1].tag !== "S",
       "6e: … riding a LEGACY colour tag, so a lost prefix never degrades to grey");
  }
//  a GREY or BLANK slot carries no O at all — nothing dead is ever coloured.
for (const f of [fUn, fSt, mDb])
  for (let i = 0; i < f.cells.length; i++)
    if (f.cells[i].tag === "D" || (f.cells[i].tag === "S" && /^ +$/.test(f.cells[i].text)))
      ok(!f.cells[i + 1] || f.cells[i + 1].tag !== "O",
         "6e: a disabled/blank slot mints nothing (" + JSON.stringify(f.cells[i].text) + ")");

//  --- 7. `Sub:` families nest, cycles do not hang ------------------------------
//  Nesting is STRUCTURE (the work.js rule), so it holds in plain too.
const fplain = render([fams], false, false);
const seq = fplain.lines.filter(function (l) { return l.length; })
                        .map(function (l) { return l.replace(/^[^A-Z]*/, "").slice(0, 7); });
eq(seq.join(","), "FAM-001,FAM-002,FAM-004,FAM-003,FAM-005,FAM-006,FAM-007,FAM-008",
   "7: a child follows its parent, a grandchild its child");
eq(lineOf(fplain, "FAM-002").indexOf("├┄┄ "), 0, "7: a non-last child rides `├┄┄ `");
eq(lineOf(fplain, "FAM-003").indexOf("└┄┄ "), 0, "7: the last child rides `└┄┄ `");
eq(lineOf(fplain, "FAM-004").indexOf("│   └┄┄ "), 0, "7: a grandchild rails one deeper");
eq(lineOf(fplain, "FAM-005").indexOf("FAM-005"), 0, "7: a cross-topic Sub: is FLAT");
eq(lineOf(fplain, "FAM-006").indexOf("FAM-006"), 0, "7: a closed-parent Sub: is FLAT");
//  7b. the CYCLE: the render terminated (we are here), both members listed once,
//  and the name-sorted FIRST was cut loose to render flat (work.js breakCycles).
eq(lineOf(fplain, "FAM-007").indexOf("FAM-007"), 0, "7b: the cycle's first member is flat");
eq(lineOf(fplain, "FAM-008").indexOf("└┄┄ "), 0, "7b: … the other hangs under it");
//  7c. nesting does not cost the row its columns (a group that HAS a wt, so the
//  fixed column set exists — see 9).
//  The wt-having ticket is the CHILD here, so the rails have to eat into the
//  KEYW leader for its frames to keep the flat rows' column.
const fam2 = render([group([
  { key: "TIC-003", title: "TIC-003: parent", prio: 2, meta: {} },
  { key: "TIC-002", title: "TIC-002: child", prio: 2, meta: { Sub: "TIC-003" } },
])], false, true);
eq(lineOf(fam2, "TIC-002").indexOf("└┄┄ "), 0, "7c: the child rails");
function frameCol(r, key) { const l = lineOf(r, key); return Array.from(l.slice(0, l.indexOf("[ i"))).length; }
eq(frameCol(fam2, "TIC-002"), frameCol(pg, "TIC-002"),
   "7c: a nested row's frames still open at the ONE column");

//  --- 8. TODO-004's inline `[value]` brackets survive, before the slots --------
const fl = render([group([{ key: "TIC-001", title: "TIC-001: med", prio: 2,
  vals: [{ text: "OPEN", spell: "todo TIC Now:OPEN" }] }])], false, true);
eq(tags(fl, "TIC-001", 8), "SSFOSNOS",
   "8: bullet, sep, key, nav-O, ` [`, value N, its O, `]`");
eq(rowCells(fl, "TIC-001").filter(function (c) { return c.tag === "N"; })[0].text,
   "OPEN", "8: the value renders");
ok(lineOf(fl, "TIC-001").indexOf("TIC-001 [OPEN] ") > 0, "8: … as ` [OPEN]` after the key");

//  --- 9. a listing where NOTHING has a wt drops the column set entirely -------
//  Fixed columns exist to ALIGN something.  Three dead ┄ cells would eat 45 of
//  a narrow terminal's columns and leave the BRO-036 elastic title none, so a
//  wt-less hunk renders `<●> KEY <title> [done]` — the bullet, nothing more.
const fptxt = fpg.lines.join("");
ok(fptxt.indexOf("[ i") < 0 && fptxt.indexOf("≡") < 0, "9: a wt-less hunk shows no frames");
ok(fptxt.indexOf("┄┄┄┄") < 0, "9: … and no dotted leader either");
ok(fptxt.indexOf("●") >= 0, "9: the bullet stays — it aligns nothing");
ok(lineOf(fpg, "FAM-001").indexOf("● FAM-001 the parent") === 0, "9: the row is bullet+key+title");
//  … while a hunk with ONE wt-having row lays the columns for ALL of them.
ok(lineOf(pg, "TIC-003").indexOf("┄") > 0, "9: one wt in the hunk lays every row's columns");


//  --- 11. the trailing DONE/DONT panel (TODO-005) -----------------------------
//  `[done]` became a PANEL: one frame, two live buttons — ` ✓` closes the ticket
//  and ` ✗` shelves it.  Frame conventions throughout: dim brackets, a dim gap,
//  and each 2-cell face its OWN click zone (never one span over both).
const prow = rowCells(pg, "TIC-002");
const pl = lineOf(pg, "TIC-002");
ok(pl.indexOf("[ ✔  ✗]") > 0, "11: the row ends in the two-button panel");
eq(pl.indexOf("[done]"), -1, "11: … the single [done] label is gone");
eq(slot({ cells: prow }, " ✗"), btnOf("dont"), "11: ✗ is a live button");
//  the panel's ✔ is the HEAVY check — the ci button's light ✓ is a different
//  glyph, so the two never collide; check each by its spell all the same.
const psp = prow.filter(function (c) { return c.tag === "O"; }).map(function (c) { return c.text; });
eq(psp[psp.length - 2], paint("done") + " done TIC-002", "11: ✓ mints `done KEY`");
eq(psp[psp.length - 1], paint("dont") + " dont TIC-002", "11: ✗ mints `dont KEY`");
//  the two faces are SEPARATE spans with a dim gap between them — one span over
//  both would make a single click zone and lose the ✗.
//  the tail spans, newest last: `[` ✓ O gap ✗ O `]` newline.
const ptail = prow.slice(-8).map(function (c) { return c.tag + ":" + c.text; }).join("|");
eq(ptail, "D:[|W: ✔|O:" + paint("done") + " done TIC-002|S: |M: ✗|O:" +
          paint("dont") + " dont TIC-002|D:]|S:\n",
   "11: the panel is bracket, face+O, gap, face+O, bracket — two click zones");
//  plain mode grows no panel at all.
ok(plain.lines.join("").indexOf("✗") < 0, "11: plain mode has no panel");

//  --- 10. the [go] button (TODO-005) ------------------------------------------
//  A wt-LESS row whose head carries `Rep:` offers the ONE creating action on the
//  board: mint `work/<KEY>` from that repo.  It sits at the LEFT EDGE of the
//  frames region and the rest keeps its ┄ leader, so the title column does not
//  move; a `Rep:`-less row keeps the pure leader.  Plain stays chrome-free.
const gopg = pg;
const gorow = rowCells(gopg, "TIC-007");
const gface = gorow.filter(function (c) { return c.tag !== "O" && c.text === "go"; })[0];
ok(!!gface, "10: a `Rep:` row paints a framed 2-cell `go` face");
ok(lineOf(gopg, "TIC-007").indexOf("[go]") > 0, "10: … inside dim frame brackets");
eq(slot({ cells: gorow }, "go"), btnOf("go"),
   "10: … as a live button — Shocking Orange over its pale wash");
const gsp = gorow.filter(function (c) { return c.tag === "O"; }).map(function (c) { return c.text; });
ok(gsp.indexOf(paint("go") + " work TIC-007 ///be") >= 0,
   "10: … minting the wt-MINT spell, context-LESS (the wt does not exist yet)");
//  the region keeps its width, so every title still lands at ONE column.
eq(titleCol(gopg, "TIC-007"), titleCol(gopg, "TIC-003"),
   "10: the [go] row's title column is the plain-leader row's");
ok(lineOf(gopg, "TIC-003").indexOf("[go]") < 0, "10: a `Rep:`-less row shows no button");
ok(/┄{20}/.test(lineOf(gopg, "TIC-003")), "10: … just the plain leader");
const goplain = plain;
ok(goplain.lines.join("").indexOf("[go]") < 0, "10: plain mode grows no button");

io.log("test/todo/rows OK (" + tics.tickets.length + " rows, " +
       fams.tickets.length + " family rows, " + ix.size + " wts)\n");
