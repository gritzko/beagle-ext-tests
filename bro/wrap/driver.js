//  test/bro/wrap/driver.js — BRO-014 headless checks for the pager wrap toggle.
//  Drives a hunk with a logical line WIDER than `cols`, asserting the wrap MODE:
//    1. indexRows/indexAll soft-wrap (default) yields >1 display row for it;
//       no-wrap (wrap=false) yields EXACTLY 1 row, clamped to `cols` cells.
//    2. `w` flips the CURRENT view boolean in place (re-index, keep scroll).
//    3. `W` writes the per-TYPE default (be.wrap); a NEW same-type view inherits.
//  argv[2] = view/bro/pager.js, argv[3] = view/bro.js (lib).  No tty (never run()).
"use strict";
const pager = require(process.argv[2]);
const bro = require(process.argv[3]);

//  BRO-014: seed the session wrap map the loop mints (verb → boolean; true =
//  soft-wrap, false = no-wrap) so a new view resolves its type default here too.
globalThis.be = globalThis.be || {};
be.wrap = { log: false, cat: true, diff: true, status: true, ls: false, list: false };

function w(s) { const b = utf8.Encode(s); const x = io.buf(b.length + 8); x.feed(b); io.writeAll(1, x); }
function check(name, cond) { w((cond ? "ok   " : "FAIL ") + name + "\n"); }

//  A single logical line 30 cp wide + a short 2nd line; toks empty (syntax hunk).
const COLS = 10;
const wide = "abcdefghijklmnopqrstuvwxyz0123\nshort\n";     // 30-wide line, then 5
function wideHunk(uri, verb) {
  return { uri: uri, verb: verb, text: utf8.Encode(wide), toks: new Uint32Array(0), kind: "file" };
}

//  --- 1. indexRows: soft-wrap vs no-wrap over the wide line ------------------
const h = wideHunk("wide.txt#L1", "cat");
const soft = bro.indexRows(h, COLS);                        // default (no arg) = soft
const softLine1 = soft.filter(function (r) { return r.off < 30; });
check("soft-line1-wraps", softLine1.length > 1);           // 30cp / 10 → 3 rows
check("soft-true-wraps", bro.indexRows(h, COLS, true)
      .filter(function (r) { return r.off < 30; }).length > 1);
const nowrap = bro.indexRows(h, COLS, false);
const nwLine1 = nowrap.filter(function (r) { return r.off < 30; });
check("nowrap-line1-single", nwLine1.length === 1);        // one clamped row
//  The clamped row shows exactly COLS visible cells (no toks: end-off === COLS).
check("nowrap-clamp-cols", nwLine1[0].end - nwLine1[0].off === COLS);
//  No-wrap keeps the SECOND logical line as its own row (skip-to-'\n' worked).
const nwShort = nowrap.filter(function (r) { return r.off > 30; });
check("nowrap-line2-present", nwShort.length === 1 &&
      utf8.Decode(h.text.subarray(nwShort[0].off, nwShort[0].end)) === "short");

//  indexAll carries the mode too (banner + clamped body rows).
const allSoft = pager.indexAll([h], COLS, true);           // soft
const allNowrap = pager.indexAll([h], COLS, false);        // no-wrap
check("indexAll-nowrap-fewer", allNowrap.length < allSoft.length);
//  No-wrap = 1 banner + 2 body rows (the two logical lines), each clamped.
check("indexAll-nowrap-rows", allNowrap.length === 3 && allNowrap[0].banner === true);

//  --- 2. `w` flips the CURRENT view in place, keeping the scroll -------------
//  A `cat` view opens soft (be.wrap.cat === true); `w` flips it to no-wrap.
const realSize = tty.size;
tty.size = function () { return { rows: 24, cols: COLS }; };
const p = new pager.Pager(-1, { color: false });
p.setHunks([h]);
p.view.verb = "cat"; p.view.wrap = pager_wrapFor("cat");   // open in the type default
p.rows(COLS);
const beforeRows = p.view.rows.length;
check("wrap-default-soft", p.view.wrap === true);          // cat defaults soft (true)
p.key(0x77);                                                // w  → no-wrap
check("w-sets-nowrap", p.view.wrap === false);
const afterRows = p.rows(COLS).length;
check("w-reindexes-fewer", afterRows < beforeRows);
p.key(0x77);                                                // w  → back to soft
check("w-flips-back", p.view.wrap === true);
check("w-reindex-restore", p.rows(COLS).length === beforeRows);

//  --- 3. `W` sets the per-TYPE default; a NEW same-type view inherits it -----
//  Use `cat` (a soft-default type, be.wrap.cat === true): toggle this view to
//  no-wrap, `W` writes be.wrap.cat = false, a NEW cat view then opens no-wrap.
const p2 = new pager.Pager(-1, { color: false, driveSpell: function (s) {
  return [wideHunk("c2.txt#L1", "cat")];
} });
p2.setHunks([wideHunk("c1.txt#L1", "cat")]);
p2.view.verb = "cat"; p2.view.uri = "c1.txt#L1"; p2.view.wrap = pager_wrapFor("cat");
p2.rows(COLS);
check("W-view-starts-soft", p2.view.wrap === true);        // cat defaults soft
p2.key(0x77);                                               // w  → this view no-wrap
p2.key(0x57);                                               // W  → cat default = false
check("W-writes-be-wrap", be.wrap.cat === false);
p2._runSpell("cat:");                                      // a NEW cat view
check("W-new-view-nowrap", p2.view.wrap === false &&
      p2.view.hunks[0].uri === "c2.txt#L1");
//  A DIFFERENT type is unaffected by the cat override (status defaults soft).
const p3 = new pager.Pager(-1, { color: false, driveSpell: function (s) {
  return [wideHunk("st.txt#L1", "status")];
} });
p3.setHunks([wideHunk("wide.txt#L1", "status")]);
p3.view.verb = "status"; p3.view.uri = "wide.txt#L1";
p3._runSpell("status:");
check("W-other-type-soft", p3.view.wrap === true);
//  An UNLISTED type defaults to soft (true); a listed no-wrap type opens no-wrap.
check("unlisted-defaults-soft", pager_wrapFor("grep") === true);
check("listed-log-nowrap", pager_wrapFor("log") === false);

tty.size = realSize;

//  --- 4. SHORTCUTS: `w`/`W` are single-sourced so the help view mirrors them -
const keys = pager.SHORTCUTS.map(function (r) { return r[0]; }).join(" ");
check("shortcuts-has-w", keys.indexOf("w") >= 0 && keys.indexOf("W") >= 0);

//  BRO-014: the type-default resolver (be.wrap[type], unlisted → true) the pager
//  uses at view-open; re-derived here so the driver seeds the SAME polarity.
function pager_wrapFor(verb) {
  const v = be.wrap ? be.wrap[verb || ""] : undefined;
  return v === undefined ? true : v;
}

w("DONE\n");
