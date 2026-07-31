//  CFOLD-001: dump `<bucket> <path>` for one wt through the REAL status
//  classifier (shared/classify.js — what views/status/status.js calls), so the
//  case's golden pins the EXPECTED-derived KINDS (pat/mrg/mod), which the quad
//  `--plain` columns collapse.  Args: <wt-dir>.
"use strict";

//  DIS-054 isolated-clone require: derive the be/ code dir from this script's
//  own path (`<be>/test/status/cfold/buckets.js` → `<be>`).
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const classify = _req("shared/classify.js");
const wtlog = _req("shared/wtlog.js");
const store = _req("shared/store.js");
const discover = _req("core/discover.js");

const wt = process.argv[2];
if (!wt) throw "usage: buckets.js <wt-dir>";
const info = discover.treeAt(wt);
const res = classify.classify({ wt: info.wt }, wtlog.open(info),
                              store.open(info.storePath, info.project));
const lines = [];
for (const r of res.rows) lines.push(r.bucket + " " + r.path);
lines.sort();
const u = utf8.Encode(lines.join("\n") + "\n");
const b = io.buf(u.length + 8); b.feed(u); io.writeAll(1, b);
