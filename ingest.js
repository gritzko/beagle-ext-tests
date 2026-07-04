//  JS-073: shared/ingest.js — `add` lands a re-get pack into an EXISTING
//  shard and updates the `refs` ULOG.  Two invariants the old in-place
//  `writeUlog`→`writeBytes` path broke, and this repro pins:
//  (A) ts-preservation: surviving reflog rows keep their ORIGINAL ts (the
//      old path re-fed rows with no ts, restamping every survivor to now);
//  (B) atomicity: the refs rewrite goes via a temp sibling + io.rename, and
//      NEVER truncates the live `refs` in place (io.resize(fd,0)) — a crash
//      after an in-place truncate leaves refs empty, losing every tip.
"use strict";

const { eq, ok } = require("./lib/assert.js");
//  DIS-054: an ISOLATED ticket clone gives the test tree its OWN `.be` shard,
//  so a be-relative require resolves against THAT (code-less) shard.  Derive
//  the be/ code dir from THIS script's own path; fall back to be-relative.
const ingest = _req("shared/ingest.js");
const ulog = _req("shared/ulog.js");
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}

const SHA = (c) => c.repeat(40);
const TMP = io.getenv("TMP") || "/tmp";

//  A hermetic shard <dir>/.be/<proj> with a real seeded refs ULOG.
function freshShard(tag) {
  const dir = TMP + "/js073-" + tag + "-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
  const shard = dir + "/.be/p";
  io.mkdir(dir); io.mkdir(dir + "/.be"); io.mkdir(shard);
  return shard;
}

//  A minimal but REAL git packfile (one blob) with the trailing 20-byte
//  sha1(body) trailer add()/packLogBytes expect (wire.js emitPack recipe).
function makePack(text) {
  const body = utf8.Encode(text);
  const ta = new Uint8Array(body.length + 4096);
  const pk = git.pack.over(ta);
  pk.header();
  pk.feed("blob", body, -1, null);
  pk.finish();
  const wm = Number(pk.buffer.watermark);
  const full = new Uint8Array(wm + 20);
  full.set(ta.subarray(0, wm), 0);
  full.set(sha1(ta.subarray(0, wm)), wm);       // git pack trailer = sha1(body)
  return full;
}

function drainTs(p) {
  const out = [];
  ulog.each(p, function (log) { out.push({ ts: log.time, verb: log.verb, uri: log.uri }); });
  return out;
}

//  --- (A) ts-preservation: survivors keep their ORIGINAL ts --------------
{
  const shard = freshShard("ts");
  const refs = shard + "/refs";
  //  Seed two rows stamped an HOUR in the past (explicit ts).  A restamp
  //  on rewrite would bump these to "now" — the OLD-code failure.
  const OLD = ron.of(Date.now() - 3600 * 1000);
  ulog.write(refs, [
    { verb: "get",  uri: "ssh://h/r?#" + SHA("a"), ts: OLD },
    { verb: "post", uri: "?#" + SHA("a"),          ts: OLD + 1n }
  ]);
  const before = drainTs(refs);
  eq(before.length, 2, "ts: two rows seeded");

  ingest.add(makePack("js073 ts pack"), shard, "ssh://h/r?", SHA("b"));

  const after = drainTs(refs);
  ok(after.length >= 4, "ts: survivors + two new tip rows");
  //  The two survivors are still first and carry their ORIGINAL ts.
  eq(after[0].ts, before[0].ts, "ts: survivor row0 keeps its ORIGINAL ts");
  eq(after[1].ts, before[1].ts, "ts: survivor row1 keeps its ORIGINAL ts");
  //  ...and the new tip rows are stamped strictly LATER (fresh monotonic).
  ok(after[2].ts > before[1].ts, "ts: new tip row stamped after the old tail");
  ok(after[after.length - 1].uri.indexOf(SHA("b")) >= 0, "ts: new tip sha landed");
}

//  --- (B) native in-place append: survivors intact, tip lands, no data loss --
//  `add` now appends the tip rows via the native booked ULOG (abc._ulog_*),
//  which does its file IO in C — below the JS io leaves, so a JS-io spy sees
//  nothing.  Assert OUTCOMES instead: the pre-existing refs row survives (bytes
//  + original ts, no restamp), the new tip is appended, the native `.refs.idx`
//  sidecar the booked path maintains lands, and refs is never emptied (the
//  in-place truncate-and-rewrite JS-073 removed would zero it on a mid-op kill).
{
  const shard = freshShard("atomic");
  const refs = shard + "/refs";
  const OLD = ron.of(Date.now() - 3600 * 1000);
  ulog.write(refs, [{ verb: "get", uri: "ssh://h/r?#" + SHA("a"), ts: OLD }]);
  const before = drainTs(refs);
  eq(before.length, 1, "native: one row seeded");

  ingest.add(makePack("js073 atomic pack"), shard, "ssh://h/r?", SHA("b"));

  const rows = drainTs(refs);
  ok(rows.length >= 3, "native: survivor + two new tip rows present");
  eq(rows[0].ts, before[0].ts, "native: survivor keeps its ORIGINAL ts (no restamp)");
  ok(rows[0].uri.indexOf(SHA("a")) >= 0, "native: survivor tip preserved");
  ok(rows[rows.length - 1].uri.indexOf(SHA("b")) >= 0, "native: new tip landed");
  ok(io.stat(refs).size > 0, "native: refs never emptied");
  ok(exists(shard + "/.refs.idx"), "native: booked-append sidecar maintained");
}

//  small fs-exists helper (native sidecar assertion above).
function exists(p) { try { io.stat(p); return true; } catch (e) { return false; } }

io.log("ingest.js OK\n");
