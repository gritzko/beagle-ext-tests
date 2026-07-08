//  BE-011: stage.classifyNamed LOCAL self-defense guard.  classifyNamed(raw) does
//  `io.lstat(join(wtRoot, raw))` on its raw arg; today put.js pre-filters with
//  stage.isMeta(raw) BEFORE calling, and the sibling explicitMove self-guards with
//  isMeta — classifyNamed did not.  This adds the SAME local isMeta gate so stage.js
//  self-defends uniformly (DEFENSE-IN-DEPTH, not a fixed live escape).  RED against
//  pre-guard code (a `../sentinel` raw STATS outside the wt and reports the outside
//  file "exists but is not stageable"), GREEN after (refused "is a meta path", no
//  outside stat).  A minimal engine (empty baseline) exercises classifyNamed direct.
"use strict";

const { eq } = require("./lib/assert.js");
const stage = _req("shared/stage.js");
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}

const TMP = io.getenv("TMP") || "/tmp";
const base = TMP + "/js-stageguard-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
const wt = base + "/wt";
io.mkdir(base); io.mkdir(wt);
//  a benign untracked in-tree file (positive control) + an OUTSIDE sentinel that
//  "../sentinel" resolves to (the escape target the pre-guard code would stat).
function put(p, s) { const u = utf8.Encode(s); const b = io.buf(u.length + 8); b.feed(u);
                     const fd = io.open(p, "c"); io.write(fd, b); io.close(fd); }
put(wt + "/hello.txt", "hi\n");
put(base + "/sentinel", "OUTSIDE\n");

//  Minimal engine: no baseline tree, empty wtlog — classifyNamed reads only the
//  wt scan + its raw arg, which is all this guard concerns.
const beStub = { wt: wt };
const wtlogStub = { baselineTip: function () { return null; }, rows: [],
                    has: function () { return false; } };
const storeStub = { commitTree: function () { return null; },
                    readTreeRecursive: function () {} };
const eng = stage.prep(beStub, wtlogStub, storeStub);

//  --- escape: a `..` raw is refused as meta, WITHOUT stat'ing the outside file --
const esc = eng.classifyNamed("../sentinel");
eq(esc.stage, false, "classifyNamed('../sentinel').stage");
eq(esc.reason, "is a meta path", "classifyNamed('../sentinel').reason (leaked outside?)");

//  reserved-name segments are meta too.
eq(eng.classifyNamed(".git/config").reason, "is a meta path", "classifyNamed('.git/config')");
eq(eng.classifyNamed(".be").reason, "is a meta path", "classifyNamed('.be')");

//  --- benign in-tree untracked file still stages (no over-rejection) ----------
eq(eng.classifyNamed("hello.txt").stage, true, "classifyNamed('hello.txt') should stage");

function w(s){const u=utf8.Encode(s+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w("PASS stage_guard.js");
