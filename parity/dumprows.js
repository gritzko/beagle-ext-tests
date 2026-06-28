//  dumprows.js — dump a ULOG's rows as `<verb>\t<uri>` for the JSQUE-007
//  golden-diff parity harness (test/js/lib/parity.sh).  Args:
//  <ulog-path> [verb-filter].  When a verb filter is given, only rows of that
//  verb print.  `lib/ulog.js` is be-relative — it resolves the be/ shard
//  nearest this script, so the case's cwd is irrelevant.  (Same body as the
//  landed test/js/put/dumprows.js; kept beside the parity cases so the
//  `$_CASE/../dumprows.js` path resolves for test/js/parity/<case>.)
"use strict";
//  JSQUE-016 by-verb reorg moved the kernel libs lib/ -> shared/; probe the
//  new path first, fall back to the flat layout (layout-agnostic helper).
//  DIS-054: an ISOLATED ticket clone gives the test tree (`test/`) its OWN
//  `.be` shard, so a be-relative `require("shared/ulog.js")` from this script
//  resolves against THAT (code-less) shard, not the be/ code tree.  Derive the
//  be/ code dir from THIS script's own path (`<be>/test/parity/…` → up to
//  `<be>`); fall back to $BEDIR, then the be-relative form.
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
  try { return require("shared/ulog.js"); } catch (e) { return require("lib/ulog.js"); }
}
const path = process.argv[2];
const want = process.argv[3] || "";
ulog.each(path, function (log) {
  if (want && log.verb !== want) return;
  io.log(log.verb + "\t" + log.uri + "\n");
});
