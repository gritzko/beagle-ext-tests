//  dumprows.js — dump a ULOG's rows as `<verb>\t<uri>` for the put parity
//  harness (test/js/put/putcase.sh).  Args: <ulog-path> [verb-filter].
//  When a verb filter is given, only rows of that verb print.  `lib/ulog.js`
//  is be-relative — it resolves the be/ shard nearest this script, so the
//  case's cwd is irrelevant.
"use strict";
const ulog = require("shared/ulog.js");
const path = process.argv[2];
const want = process.argv[3] || "";
ulog.each(path, function (log) {
  if (want && log.verb !== want) return;
  io.log(log.verb + "\t" + log.uri + "\n");
});
