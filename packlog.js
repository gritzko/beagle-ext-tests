//  JS-117: tail-append — post/land pack RECORDS onto the highest .keeper log
//  under the size threshold instead of opening a new file per event.  Pins:
//   (a) land twice -> ONE log, TWO 0xF bookmark rows, both packs' objects read;
//   (b) writePack (post's fold) twice -> ONE log, both commits locatable;
//   (c) threshold crossing opens log 2;
//   (d) torn tail (records appended, idx NOT written, then truncated) leaves
//       every previously-indexed object readable.
"use strict";

const { eq, ok } = require("./lib/assert.js");
const ingest = _req("shared/ingest.js");
const store  = _req("shared/store.js");
const fold   = _req("verbs/post/fold-commit.js");
const sha    = _req("shared/util/sha.js");
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}

const TMP = io.getenv("TMP") || "/tmp";
function freshShard(tag) {
  const dir = TMP + "/js117-" + tag + "-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
  const shard = dir + "/.be/p";
  io.mkdir(dir); io.mkdir(dir + "/.be"); io.mkdir(shard);
  return { dir: dir, shard: shard };
}
//  A minimal real git packfile (one blob) with the 20-byte sha1 trailer.
function makePack(text) {
  const body = utf8.Encode(text);
  const ta = new Uint8Array(body.length + 4096);
  const pk = git.pack.over(ta);
  pk.header(); pk.feed("blob", body, -1, null); pk.finish();
  const wm = Number(pk.buffer.watermark);
  const full = new Uint8Array(wm + 20);
  full.set(ta.subarray(0, wm), 0);
  full.set(sha1(ta.subarray(0, wm)), wm);
  return { pack: full, sha: sha.frameSha("blob", body), body: body };
}
function keepers(shard) {
  return io.readdir(shard).filter((f) => /^\d{10}\.keeper$/.test(f)).sort();
}
//  Count the 0xF PACK bookmark rows across every idx run in the shard.
function bookmarks(shard) {
  const ix = abc.index("wh128", { dir: shard, ext: "keeper.idx" });
  let n = 0;
  //  bookmark keys are ((first_off<<20|fid)<<4)|0xF — well under 2^52; object
  //  keys (hashlet60<<4) sit far above, and 1<<64 would overflow u64 to 0.
  ix.range(0n, 1n << 52n, function (kv) {
    if ((kv[0] & 0xfn) === 0xfn) n++;
    return true;
  });
  return n;
}
function reads(r, m) {
  const o = r.getObject(m.sha);
  return o && o.type === "blob" && o.bytes.length === m.body.length &&
    Array.from(o.bytes).every((v, i) => v === m.body[i]);
}

//  --- (a) land twice -> ONE log, TWO bookmarks, both blobs read ------------
{
  const { dir, shard } = freshShard("land2");
  const m1 = makePack("js117 land pack ONE alpha");
  const m2 = makePack("js117 land pack TWO bravo different bytes");
  ingest.land(m1.pack, shard);
  eq(keepers(shard).length, 1, "land: first land opens one log");
  ingest.land(m2.pack, shard);
  eq(keepers(shard).length, 1, "land: second land APPENDS — still one log");
  eq(bookmarks(shard), 2, "land: two 0xF pack bookmark rows");
  const r = store.open(dir, "p");
  ok(reads(r, m1), "land: pack-1 blob reads through the multi-pack log");
  ok(reads(r, m2), "land: pack-2 blob (past pack 1) reads through the idx tail");
}

//  --- (b) writePack (post's fold) twice -> ONE log, both commits locatable --
{
  const { dir, shard } = freshShard("post2");
  function commit(msg, ts) {
    return fold.buildCommit({ treeSha: fold.EMPTY_TREE_SHA, parents: [],
      author: "T <t@t>", epochSec: ts, message: msg });
  }
  const c1 = commit("js117 first commit", 1000);
  const c2 = commit("js117 second commit", 2000);
  //  empty-tree commits: no wt reads (rootTreeSha undefined, no add decisions).
  fold.writePack(shard, "/nonexistent", c1.body, undefined, [], []);
  eq(keepers(shard).length, 1, "post: first writePack opens one log");
  fold.writePack(shard, "/nonexistent", c2.body, undefined, [], []);
  eq(keepers(shard).length, 1, "post: second writePack APPENDS — still one log");
  eq(bookmarks(shard), 2, "post: two 0xF pack bookmark rows");
  const r = store.open(dir, "p");
  const o1 = r.getObject(c1.sha), o2 = r.getObject(c2.sha);
  ok(o1 && o1.type === "commit", "post: commit 1 locatable");
  ok(o2 && o2.type === "commit", "post: commit 2 (past pack 1) locatable");
}

//  --- (c) threshold crossing opens log 2 -----------------------------------
{
  const { shard } = freshShard("thresh");
  const m1 = makePack("js117 threshold pack one");
  ingest.land(m1.pack, shard);
  //  Grow log 1 to the cap (sparse ftruncate) so the next land can't append.
  const fd = io.open(shard + "/0000000001.keeper", "rw");
  io.resize(fd, ingest.KEEP_LOG_MAX); io.close(fd);
  const m2 = makePack("js117 threshold pack two");
  ingest.land(m2.pack, shard);
  const logs = keepers(shard);
  eq(logs.length, 2, "threshold: over-cap log forces a NEW log 2");
  eq(logs[1], "0000000002.keeper", "threshold: log 2 is the next seq");
}

//  --- (d) torn tail: records appended, idx NOT written, then truncated ------
{
  const { dir, shard } = freshShard("torn");
  const m1 = makePack("js117 torn pack one durable");
  const m2 = makePack("js117 torn pack two also durable bytes");
  ingest.land(m1.pack, shard);
  ingest.land(m2.pack, shard);          // both indexed, one log
  const log = shard + "/0000000001.keeper";
  const good = io.stat(log).size;
  //  Simulate a crash mid-append of a THIRD pack: append its records (grow the
  //  file) but never write the idx run, then tear it mid-record.
  const m3 = makePack("js117 torn pack three THIS TAIL IS LOST forever and ever");
  const recs3 = ingest.packLogBytes(m3.pack).subarray(12).slice();
  ingest.appendRecords(log, recs3);     // records land, NO indexAppended
  io._truncate(log, good + ((recs3.length / 2) | 0));   // tear mid-record
  const r = store.open(dir, "p");
  ok(reads(r, m1), "torn: pack-1 object still readable after a torn tail");
  ok(reads(r, m2), "torn: pack-2 object still readable after a torn tail");
  eq(r.getObject(m3.sha), undefined, "torn: the unindexed torn object is dead");
}

io.log("packlog.js OK\n");
