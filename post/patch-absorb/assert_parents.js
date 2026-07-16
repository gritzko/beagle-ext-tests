//  assert_parents.js — DIS-057 RULING 2026-06-29 proof helper: dump the wt's
//  own cur tip commit's parents (one per line) so run.sh can assert the absorb
//  is a real MERGE commit (parents = ours-tip + theirs).  Run from inside the wt:
//    jab assert_parents.js
//  DIS-076: a commit is WT-only (never mints/moves a ref), so the cur tip is
//  read via wtlog, not a trunk REF (resolveRef("") never gets set).
//  Prints the parent shas (40-hex, one per line) of cur's tip to STDOUT (fd 1;
//  io.log goes to stderr, which run.sh discards).
"use strict";
function outStr(s) { const b = io.buf(s.length + 8); b.feed(utf8.Encode(s)); io.writeAll(1, b); }
const beDir = io.getenv("BEDIR") || ".";
const be = require(beDir + "/core/discover.js");
const store = require(beDir + "/shared/store.js");
const wtlog = require(beDir + "/shared/wtlog.js");
const info = be.treeAt(".");
const reader = store.open(info.storePath, info.project);
const cur = wtlog.open(info).curTip();
const tip = (cur && cur.sha) || "";
if (tip) {
  const pc = reader.parseCommit(tip);
  const ps = (pc && pc.parents) || [];
  let s = "";
  for (const p of ps) s += p + "\n";
  outStr(s);
}
