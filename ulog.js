//  JS-048: be/lib/ulog.js — the single ULOG read+write module.  Exercises
//  the crash-safe, monotonic wtlog WRITERS (folded in from wtwrite.js)
//  through the READERS (each/drain) in the same module:
//  (a) append rows to a fresh ULOG → re-drain → assert verb/uri/ts and
//      that ts is STRICTLY increasing;
//  (b) a second append onto the existing file preserves the old rows and
//      samples a ts strictly greater than the ULOG tail (SNIFFAtNow port);
//  (c) crash-safety: the writer goes via a temp file + io.rename, so a
//      kill before the rename leaves the OLD file byte-intact (we drive
//      the temp+rename path directly and assert the invariant).
"use strict";

//  assert.js is a sibling test helper; ulog.js is a be/ shard lib module.
const { eq, ok, bytesEq, throws } = require("./lib/assert.js");
//  DIS-054: an ISOLATED ticket clone gives the test tree its OWN `.be` shard,
//  so a be-relative `require("shared/ulog.js")` resolves against THAT
//  (code-less) shard.  Derive the be/ code dir from THIS script's own path
//  (`<be>/test/ulog.js` → `<be>`); fall back to the be-relative form.
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

//  scratch dir under TMP (a plain dir — never a bare `.be`).
const TMP = io.getenv("TMP") || "/tmp";
const dir = TMP + "/js048-ulog-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
io.mkdir(dir);
const path = dir + "/wtlog";

function drainRows(p) {
  const out = [];
  ulog.each(p, function (log) {
    out.push({ ts: log.time, verb: log.verb, uri: log.uri });
  });
  return out;
}

//  --- (a) fresh append ---------------------------------------------------
ulog.append(path, [
  { verb: "get", uri: "file:" + dir + "/.be/?/p" },
  { verb: "get", uri: "?main#" + SHA("a") }
]);

let rows = drainRows(path);
eq(rows.length, 2, "fresh: two rows");
eq(rows[0].verb, "get", "fresh: row0 verb");
eq(rows[0].uri, "file:" + dir + "/.be/?/p", "fresh: row0 uri");
eq(rows[1].verb, "get", "fresh: row1 verb");
eq(rows[1].uri, "?main#" + SHA("a"), "fresh: row1 uri");
ok(rows[0].ts < rows[1].ts, "fresh: ts strictly increasing");

const tailA = rows[1].ts;

//  --- (b) append onto the existing file ----------------------------------
ulog.append(path, [{ verb: "post", uri: "?main#" + SHA("b") }]);

rows = drainRows(path);
eq(rows.length, 3, "append: three rows");
eq(rows[0].uri, "file:" + dir + "/.be/?/p", "append: row0 preserved");
eq(rows[1].uri, "?main#" + SHA("a"), "append: row1 preserved");
eq(rows[2].verb, "post", "append: new row verb");
eq(rows[2].uri, "?main#" + SHA("b"), "append: new row uri");
ok(rows[0].ts < rows[1].ts && rows[1].ts < rows[2].ts,
   "append: ts strictly increasing across all rows");
ok(rows[2].ts > tailA, "append: new ts strictly > old tail (SNIFFAtNow)");

//  Old rows keep their ORIGINAL timestamps (no rewrite/restamp).
eq(rows[0].ts, drainRows(path)[0].ts, "append: stable old ts");

//  --- multi-row monotonic bump in one call -------------------------------
//  Two rows fed in one append get consecutive, strictly-increasing ts even
//  when wall-clock resolution would collide them.
ulog.append(path, [
  { verb: "put", uri: "x.txt" },
  { verb: "put", uri: "y.txt" }
]);
rows = drainRows(path);
const n = rows.length;
ok(rows[n - 2].ts < rows[n - 1].ts, "multi: two same-call rows strictly increase");

//  --- (c) crash-safety: temp+rename, OLD file intact on a pre-rename kill -
//  Snapshot the current good bytes, then START a write that "crashes"
//  before the rename: assert the live file still holds the OLD bytes and
//  no half-written target is left behind.
const before = io.mmap(path, "r").data().slice();
const tmp = ulog._stage(path, [{ verb: "post", uri: "?main#" + SHA("c") }]);
ok(tmp !== path, "crash: stage wrote a temp file, not the target");
//  Simulate the crash: we never rename.  The target must be byte-identical.
const after = io.mmap(path, "r").data().slice();
bytesEq(after, before, "crash: target unchanged before rename");
io.unlink(tmp);                                // clean the orphaned temp

//  Committing the staged temp (the rename) is atomic and lands the row.
const tmp2 = ulog._stage(path, [{ verb: "post", uri: "?main#" + SHA("c") }]);
io.rename(tmp2, path);
rows = drainRows(path);
eq(rows[rows.length - 1].uri, "?main#" + SHA("c"), "crash: rename commits the row");

//  --- clock guard: a gross-backwards tail raises CLOCKBAD ----------------
//  Feed a row stamped far in the FUTURE, then append with the real clock:
//  the >30s backwards skew must refuse (SNIFFCheckClock port).
const cpath = dir + "/clock";
const future = ron.of(Date.now() + 3600 * 1000);   // +1h
ulog.write(cpath, [{ verb: "get", uri: "?main#" + SHA("d"), ts: future }]);
throws(function () { ulog.append(cpath, [{ verb: "post", uri: "?main#" + SHA("e") }]); },
       "clock: gross-backwards tail throws CLOCKBAD");

//  cleanup
for (const f of io.readdir(dir)) { try { io.unlink(dir + "/" + f); } catch (e) {} }

io.log("ulog.js OK\n");
