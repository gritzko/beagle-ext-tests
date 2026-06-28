//  dumprows.js — dump a ULOG's rows as `<verb>\t<uri>` for the put parity
//  harness (test/js/put/putcase.sh).  Args: <ulog-path> [verb-filter].
//  When a verb filter is given, only rows of that verb print.  `lib/ulog.js`
//  is be-relative — it resolves the be/ shard nearest this script, so the
//  case's cwd is irrelevant.
"use strict";
//  DIS-054: an ISOLATED ticket clone gives the test tree its OWN `.be` shard,
//  so a be-relative `require("shared/ulog.js")` from this probe resolves
//  against THAT (code-less) shard.  Derive the be/ code dir from THIS script's
//  own path (`<be>/test/put/…` → `<be>`); fall back to $BEDIR, then be-relative.
const ulog = _loadUlog();
function _loadUlog() {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  const cands = [];
  if (self) { const d = self.slice(0, self.lastIndexOf("/test/")); if (d && d !== self) cands.push(d); }
  const env = (typeof io !== "undefined" && io.getenv) ? io.getenv("BEDIR") : "";
  if (env) cands.push(env);
  for (const d of cands) for (const p of ["/shared/ulog.js", "/lib/ulog.js"]) {
    try { return require(d + p); } catch (e) {}
  }
  return require("shared/ulog.js");
}
const path = process.argv[2];
const want = process.argv[3] || "";
ulog.each(path, function (log) {
  if (want && log.verb !== want) return;
  io.log(log.verb + "\t" + log.uri + "\n");
});
