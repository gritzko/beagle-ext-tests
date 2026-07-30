//  STATUS-017 (DIS-080 §6): the KIND of a patched path's dirt comes from the
//  EXPECTED reading (base ⊕ the in-scope patch-ins, via the weave), NOT from the
//  DIS-057 mtime band — so it survives a restamp, and a local edit on top of a
//  patched file reads `mod`, not `pat`/`mrg`.  Args: <wt-dir>.  Throw = ctest RED.
"use strict";

const { eq, ok } = require("../../lib/assert.js");

//  DIS-054 isolated-clone require: derive the be/ code dir from this script's
//  own path (`<be>/test/status/expected-kinds/assert.js` → `<be>`).
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

function writeF(p, s) {
  const u = utf8.Encode(s); const b = io.buf(u.length + 8); b.feed(u);
  const fd = io.open(p, "c"); io.writeAll(fd, b); io.close(fd);
}

const wt = process.argv[2];
ok(wt, "usage: assert.js <wt-dir>");
const info = discover.treeAt(wt);
const wtl = wtlog.open(info);
const reader = store.open(info.storePath, info.project);

let prow = null;
for (const r of wtl.rows) if (r.verb === "patch") prow = r;
ok(prow, "a patch row was appended to the wtlog");

function buckets() {
  const res = classify.classify({ wt: info.wt }, wtl, reader);
  const m = {};
  for (const r of res.rows) m[r.path] = r.bucket;
  return m;
}

//  1. straight after the absorb: EXPECTED and the band agree.
let m = buckets();
eq(m["f-take.txt"], "pat", "a clean take-theirs is pat");
eq(m["f-merge.txt"], "mrg", "a real weave merge is mrg");
eq(m["keep.txt"], undefined, "an untouched file stays clean (count-only ok)");

//  2. band DESTROYED (mtime only, bytes untouched) — the kinds must survive.
const off = ulog.ronStepMs(prow.ts, 5);          // outside the band, not a row ts
io.setMtime(wt + "/f-take.txt", off);
io.setMtime(wt + "/f-merge.txt", off);
m = buckets();
eq(m["f-take.txt"], "pat", "restamped take-theirs is still pat (EXPECTED, not the band)");
eq(m["f-merge.txt"], "mrg", "restamped weave is still mrg (EXPECTED, not the band)");

//  3. a LOCAL edit on top of a patched path is no longer the patched-in dirt.
writeF(wt + "/f-take.txt", "take a\nMINE b\ntake c\n");
m = buckets();
eq(m["f-take.txt"], "mod", "a local edit over a patched file is mod, not pat");
eq(m["f-merge.txt"], "mrg", "its sibling is untouched — still mrg");

/* clean exit = GREEN */
