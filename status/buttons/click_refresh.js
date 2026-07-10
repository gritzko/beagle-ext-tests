//  test/status/buttons/click_refresh.js — BE-041 click behaviour: a mouse
//  click on a `[put]`/`[del]` button runs its MUTATION spell and re-renders
//  the CURRENT view in place — NO result screen, NO back-stack push; a click
//  on the filename (its hidden `U` nav, a VIEW spell) still pushes.  Headless
//  Pager over a real `jab status --tlv` capture, driveSpell stubbed to a
//  recorder (the rowclick/check.js harness pattern).
//
//  Usage:  (cd <wt> && jab click_refresh.js <tlv-file>)
//  cwd must sit under a be/ shard: loop.isMutation be-climbs from cwd.
"use strict";

const pager    = require("views/bro/pager.js");
//  core/loop.js is entry-shim-only (its `_here` reads argv[1]) — probe via the
//  SAME registry call loop._isMutation makes; the loop wiring itself is the
//  pty smoke's job.
const registry = require("core/registry.js");
function isMutation(w) { return registry.verbFile(w, undefined, ["verbs"]) !== null; }
function isVerb(w) { return registry.verbFile(w) !== null; }

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }
function eq(a, b, m) { if (a !== b) fail(m + ": " + JSON.stringify(a) + " !== " + JSON.stringify(b)); }

//  The gate must classify the button verbs as mutations and the nav verbs as
//  views — assert the probe itself first (a broken be-climb here would
//  silently turn every click into a push).
ok(isMutation("put"), "isMutation(put)");
ok(isMutation("delete"), "isMutation(delete)");
ok(!isMutation("diff"), "diff is a VIEW, not a mutation");
ok(!isMutation("cat"), "cat is a VIEW, not a mutation");

//  Load the captured --tlv stream into hunks.
const st = io.lstat(process.argv[2]);
const sz = Number(st.size);
const fd = io.open(process.argv[2], "r");
const rb = io.buf(sz + 16);
io.readAll(fd, rb, sz);
io.close(fd);
const hunks = pager.hunksFromTlv(rb.data().slice());
ok(hunks.length >= 1, "status produced at least one hunk");

const COLS = 80, ROWS = 24;
const realSize = tty.size;
tty.size = function () { return { rows: ROWS, cols: COLS }; };

//  driveSpell recorder: every driven spell is logged; a fake one-hunk view is
//  returned so pushes/refreshes succeed and are observable.
const driven = [];
function stubDrive(s) {
  driven.push(s);
  return [{ uri: "stub:" + s, verb: "hunk", kind: "file",
            text: utf8.Encode("stub\n"), toks: Uint32Array.from([(18 << 27) | 5]) }];
}

//  Scan the visible grid for the cell whose click target is `spell` — the
//  token-precise cell right before the hidden O/U (pager._uriAt's contract).
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

//  --- 1. a [put] button click: drive `put …`, refresh in place, no push -----
let p = new pager.Pager(-1, { color: false, driveSpell: stubDrive,
                              isVerb: isVerb, isMutation: isMutation });
p.setHunks(hunks);
const putCell = findCell(p, "put mod.txt");
ok(putCell, "found the [put] button cell for mod.txt");
driven.length = 0;
p._mouse("0;" + putCell.col + ";" + putCell.row, true);
eq(driven[0], "put mod.txt", "the click drove the put spell");
eq(driven.length, 2, "then ONE refresh re-drive, nothing else");
eq(driven[1].split(" ")[0], "status", "the refresh re-drives the STATUS view");
eq(p.stack.length, 0, "no back-stack push (no result screen)");

//  --- 2. a [del] button click: same in-place contract for `delete …` --------
p = new pager.Pager(-1, { color: false, driveSpell: stubDrive,
                          isVerb: isVerb, isMutation: isMutation });
p.setHunks(hunks);
const delCell = findCell(p, "delete mis.txt");
ok(delCell, "found the [del] button cell for mis.txt");
driven.length = 0;
p._mouse("0;" + delCell.col + ";" + delCell.row, true);
eq(driven[0], "delete mis.txt", "the click drove the delete spell");
eq(driven.length, 2, "then ONE refresh re-drive, nothing else");
eq(p.stack.length, 0, "no back-stack push (no result screen)");

//  --- 3. a filename (U nav) click: the push-nav behaviour is UNCHANGED ------
p = new pager.Pager(-1, { color: false, driveSpell: stubDrive,
                          isVerb: isVerb, isMutation: isMutation });
p.setHunks(hunks);
const navCell = findCell(p, "diff mod.txt");
ok(navCell, "found the filename nav cell for mod.txt");
driven.length = 0;
p._mouse("0;" + navCell.col + ";" + navCell.row, true);
eq(driven.length, 1, "the nav click drives the view spell only");
eq(driven[0], "diff mod.txt", "the click drove the diff view");
eq(p.stack.length, 1, "the view PUSHED (back-stack grew)");

tty.size = realSize;
io.log("test/status/buttons click_refresh OK\n");
