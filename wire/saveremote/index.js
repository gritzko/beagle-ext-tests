//  GIT-016 test/wire/saveremote — ingest.saveRemoteRef records a remote-tracking
//  refs row that store.eachRemote reads back; a newer tip supersedes the old one
//  and the local trunk row is untouched.  Pure unit (no keeper/network).
"use strict";

const { eq, ok } = require("../../lib/assert.js");
const ingest = require("../../../shared/ingest.js");
const store  = require("../../../shared/store.js");

const TMP = io.getenv("TMP") || "/tmp";
const dir = TMP + "/git016-saveremote-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
const proj = "p";
const shard = dir + "/.be/" + proj;
io.mkdir(dir); io.mkdir(dir + "/.be");

const SHA = (c) => c.repeat(40);
const REMOTE = "ssh://localhost/repo.git?main";

//  Seed a LOCAL trunk row (store.set creates the shard + refs), then record a
//  remote-tracking tip.
store.createShard(shard);
store.set(shard, "", SHA("a"));
ingest.saveRemoteRef(shard, REMOTE, SHA("b"));

//  --- eachRemote reads back the recorded tip -----------------------------
function remotes() {
  const out = [];
  store.open(dir, proj).eachRemote(function (rt) { out.push(rt); });
  return out;
}
let rs = remotes();
eq(rs.length, 1, "one remote-tracking row recorded");
eq(rs[0].host, "localhost", "remote host is the peer authority");
eq(rs[0].sha, SHA("b"), "remote-tracking tip is the saved sha");

//  The LOCAL trunk row is untouched by the remote save.
eq(store.open(dir, proj).resolveRef(""), SHA("a"), "local trunk row untouched");

//  --- a newer tip supersedes the old (latest row per key wins) -----------
ingest.saveRemoteRef(shard, REMOTE, SHA("c"));
rs = remotes();
eq(rs.length, 1, "still one remote-tracking key after the update");
eq(rs[0].sha, SHA("c"), "newer remote tip supersedes the old one");

//  Trunk STILL untouched after the second remote save.
eq(store.open(dir, proj).resolveRef(""), SHA("a"), "local trunk row still untouched");

//  cleanup
for (const f of io.readdir(shard)) { try { io.unlink(shard + "/" + f); } catch (e) {} }

io.log("wire/saveremote OK\n");
