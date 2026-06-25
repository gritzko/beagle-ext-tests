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
let ulog;
try { ulog = require("shared/ulog.js"); }
catch (e) { ulog = require("lib/ulog.js"); }
const path = process.argv[2];
const want = process.argv[3] || "";
ulog.each(path, function (log) {
  if (want && log.verb !== want) return;
  io.log(log.verb + "\t" + log.uri + "\n");
});
