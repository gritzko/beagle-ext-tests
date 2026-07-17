//  PATCH-013: VERIFY the DIS-057 band invariant on a REAL patched wt — every
//  file the patch wrote carries its outcome's band slot as its on-disk mtime
//  (row ceil-2ms pat / ceil-1ms mrg / ceil cnf, slots via ulog.ronStepMs from
//  the PERSISTED patch row), status reads pat/mrg/con back, and a clean apply
//  costs ZERO content reads (io.open hook) — the stamp IS the outcome.
//  Args: <wt-dir>.  Throw = ctest RED.
"use strict";

const { eq, ok } = require("../../lib/assert.js");

//  DIS-054 isolated-clone require: derive the be/ code dir from this script's
//  own path (`<be>/test/patch/stampband/assert.js` → `<be>`).
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const ulog = _req("shared/ulog.js");
const classify = _req("shared/classify.js");
const wtlog = _req("shared/wtlog.js");
const store = _req("shared/store.js");
const discover = _req("core/discover.js");

const wt = process.argv[2];
ok(wt, "usage: assert.js <wt-dir>");
const info = discover.treeAt(wt);
const wtl = wtlog.open(info);

//  the persisted patch row — its ts is the band CEILING (DIS-057 Task 2).
let prow = null;
for (const r of wtl.rows) if (r.verb === "patch") prow = r;
ok(prow, "a patch row was appended to the wtlog");
const cnf = prow.ts;
const mrg = ulog.ronStepMs(cnf, -1);
const pat = ulog.ronStepMs(cnf, -2);

//  (a) each affected file's ON-DISK mtime == its exact band slot.
function mtime(rel) { return io.lstat(wt + "/" + rel).mtime; }
const PAT = ["f-take.txt", "sub/f-deep.txt", "f-add.txt", "sub/f-newadd.txt", "slink"];
for (const p of PAT) eq(mtime(p), pat, "pat slot mtime: " + p);
eq(mtime("f-merge.txt"), mrg, "mrg slot mtime: f-merge.txt");
eq(mtime("f-conf.txt"), cnf, "cnf slot mtime: f-conf.txt");
//  unaffected files must NOT sit anywhere in the band (mtimes untouched —
//  run.sh also compares their pre/post-patch stat ns byte-for-byte).
for (const p of ["own.txt", "keep.txt"])
  for (const s of [pat, mrg, cnf])
    ok(mtime(p) !== s, "unaffected " + p + " must not carry a band stamp");

//  (b) an immediate classify reads the outcome BACK from the stamps, with
//  ZERO content reads (io.open) on the clean-apply (pat) files.
const reader = store.open(info.storePath, info.project);
const realOpen = io.open;
const opened = [];
io.open = function (p) { opened.push(String(p)); return realOpen.apply(io, arguments); };
let res;
try { res = classify.classify({ wt: info.wt }, wtl, reader); }
finally { io.open = realOpen; }

const buckets = {};
for (const r of res.rows) buckets[r.path] = r.bucket;
for (const p of PAT) eq(buckets[p], "pat", "status bucket for " + p);
eq(buckets["f-merge.txt"], "mrg", "status bucket for f-merge.txt");
eq(buckets["f-conf.txt"], "con", "status bucket for f-conf.txt");
eq(res.counts.mod, 0, "no band file degrades to mod");
ok(res.counts.ok >= 2, "own.txt + keep.txt stay clean (count-only ok)");
for (const p of PAT)
  for (const o of opened)
    ok(o.indexOf("/" + p) < 0 && o !== p,
       "clean apply must be read-free: io.open(" + o + ") touched " + p);

/* clean exit = GREEN */
