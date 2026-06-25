//  reanchor.js — re-point a forked worktree's store anchor at its OWN `.be`.
//  After `cp -a base nat`, row-0 of nat/.be/wtlog still reads
//  `get file:<base>/.be/<proj>/`, so `be` resolves the store back to the
//  SHARED base shard — two forks then collide on ref writes.  This rewrites
//  row-0's path to the copy's own `.be/<proj>/` so each fork is isolated
//  (the cp -a already duplicated the shard dir).  Args: <wt-dir>.
//  Shared by the test/js/{put,delete} fork_pair (isolated ref/branch parity).
"use strict";
//  JSQUE-016 by-verb reorg moved the kernel libs lib/ -> shared/; probe the
//  new path first, fall back to the flat layout (layout-agnostic helper).
let ulog;
try { ulog = require("shared/ulog.js"); }
catch (e) { ulog = require("lib/ulog.js"); }     // be-relative: the be/ shard's ulog
const wt = process.argv[2];
const bePath = wt + "/.be/wtlog";

const rows = [];
ulog.each(bePath, function (log) {
  rows.push({ verb: log.verb, uri: log.uri, ts: log.time });
});
if (!rows.length) throw "reanchor: empty wtlog at " + bePath;

//  Row 0 is the store anchor `<scheme>:<path>/.be/<proj>/...`.  Rewrite the
//  `/.be/` path prefix to this wt's own `.be` (everything up to and
//  including `/.be/` is replaced; the `<proj>/` tail is preserved).
const u = new URI(rows[0].uri);
const p = u.path || "";
const i = p.indexOf("/.be/");
if (i < 0) throw "reanchor: row-0 has no /.be/ segment: " + rows[0].uri;
const tail = p.slice(i);                       // `/.be/<proj>/`
const scheme = u.scheme ? (u.scheme + ":") : "";
rows[0].uri = scheme + wt + tail;

//  Rewrite in place, preserving every row's original ts (ulog.write honours
//  an explicit ts per row).
ulog.write(bePath, rows);
