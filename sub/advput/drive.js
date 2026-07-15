//  BE-049: pager [put] over a mounted submodule — two arms.
//  ARM 1 (context threading): the view is NAV'D INTO the sub; a [put] button's
//  O-spell carries a SUB-relative row path, and _actSpell must thread the FULL
//  nav context (`//WT/vendor/sub`) so the put stages IN the sub (was: a
//  path-less `//host` context → the parent tree → PUTNONE).
//  ARM 2 (adv row button): the parent status' `adv vendor/sub` row (sub tip
//  ahead of the gitlink pin) must RENDER a [put] button in the pager TUI, and
//  clicking it stages the parent gitlink bump `put vendor/sub#<tip>` (was: no
//  button at all — `adv` missing from ACT_PUT; and the put itself PUTNONE'd).
"use strict";
if (typeof process !== "undefined" && process.argv) process.argv[1] = io.cwd() + "/jsrc/loop.js";
const loop  = require("core/loop.js");
const bro   = require("views/bro/bro.js");
const pager = require("views/bro/pager.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }

const wt = io.cwd().slice(io.cwd().lastIndexOf("/") + 1);         // "cli"

//  Record the context each driveSpell run threads; delegate to the REAL one.
const threaded = [];
function recDrive(spell, context) {
  threaded.push({ spell: spell, context: context });
  return bro.driveSpell(spell, context) || [];
}

const COLS = 100, ROWS = 40;
const realSize = tty.size;
tty.size = function () { return { rows: ROWS, cols: COLS }; };

function mkPager(ctx) {
  const p = new pager.Pager(-1, { color: false, driveSpell: recDrive,
                                  isVerb: loop.isVerb, isMutation: loop.isMutation,
                                  isTty: loop.isTty });
  p.setHunks(bro.driveSpell("status", ctx));
  p.view.call = { verb: "status", spell: "status", context: ctx };
  p.ctx = ctx;
  return p;
}

//  Scan the visible grid for the cell whose click target is `spell` — the
//  token-precise cell right before the hidden O (the click_refresh pattern).
function findCell(p, spell) {
  const rows = p.view.rows || p.rows(COLS);
  for (let dr = 0; dr < rows.length && dr < ROWS; dr++)
    for (let col = 1; col <= COLS; col++) {
      const hit = p._screenToByte(dr - p.view.scroll + 1, col);
      if (!hit) continue;
      if (p._uriAt(hit.hunk, hit.off) === spell) return { row: dr + 1, col: col };
    }
  return null;
}

//  --- ARM 1: nav'd-into-the-sub context threading ---------------------------
const subCtx = "//" + wt + "/vendor/sub";
let p = mkPager(subCtx);
threaded.length = 0;
p._actSpell("put x/f");
ok(threaded.length >= 1, "arm1: the spell drove");
io.log("arm1 threaded: " + JSON.stringify(threaded[0].context) + "  <= " + threaded[0].spell + "\n");
ok(threaded[0].context === subCtx, "arm1: full sub context threaded, got " + JSON.stringify(threaded[0].context));
ok((p.message || "").indexOf("PUTNONE") < 0, "arm1: no PUTNONE: " + p.message);

//  --- ARM 2: the adv row renders [put]; the click stages the gitlink bump ----
const parCtx = "//" + wt;
p = mkPager(parCtx);
const cellHit = findCell(p, "put vendor/sub");
ok(cellHit, "arm2: the adv row RENDERS a [put] button (O spell `put vendor/sub`)");
threaded.length = 0;
p._mouse("0;" + cellHit.col + ";" + cellHit.row, true);
ok(threaded.length >= 1 && threaded[0].spell === "put vendor/sub",
   "arm2: the click drove `put vendor/sub`, got " + JSON.stringify(threaded));
io.log("arm2 threaded: " + JSON.stringify(threaded[0].context) + "  <= " + threaded[0].spell + "\n");
io.log("arm2 message: " + (p.message || "") + "\n");
ok((p.message || "").indexOf("PUTNONE") < 0, "arm2: no PUTNONE: " + p.message);
ok(p.stack.length === 0, "arm2: no back-stack push (in-place refresh)");

tty.size = realSize;
io.log("drive OK\n");
