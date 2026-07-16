//  POST-027 post/push-saveref probe — after run.sh's successful FF push, the
//  LOCAL store must carry a remote-tracking refs row for the ssh peer at the
//  pushed tip (pushRemote's ingest.saveRemoteRef call, verbs/post/post.js).
//  Reuses the wire/saveremote read-back: store.eachRemote over the pushed
//  worktree's shard (auto-detected project).  Env: PROBE_WT (the wt dir),
//  PROBE_TIP (cur's 40-hex tip).
"use strict";

const { eq, ok } = require("../../lib/assert.js");
const store = require("../../../shared/store.js");

const wt  = io.getenv("PROBE_WT");
const tip = io.getenv("PROBE_TIP");
ok(wt, "PROBE_WT env present");
ok(tip && /^[0-9a-f]{40}$/.test(tip), "PROBE_TIP env is a 40-hex sha");

const rows = [];
store.open(wt, "").eachRemote(function (rt) { rows.push(rt); });
ok(rows.length >= 1, "store carries at least one remote-tracking row");

const hits = rows.filter(function (r) {
  return r.host === "localhost" && r.sha === tip;
});
if (!hits.length)
  for (const r of rows)
    io.log("row: host=" + r.host + " query=" + r.query + " sha=" + r.sha + "\n");
eq(hits.length >= 1, true, "localhost remote-tracking row at the pushed tip");

io.log("post/push-saveref probe OK\n");
