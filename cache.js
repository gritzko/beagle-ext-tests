//  BRO-043: shared/cache.js — the per-repo view cache dropped by the watcher.
//  Legs: (A) a failed watcher start leaves the cache null and EVERY read
//  recomputes (the whole safety argument); (B) miss→hit on one repo; (C) a
//  write drops that repo AND its ancestors, never a sibling or a descendant;
//  (D) an `fsw.OVERFLOW` record drops everything; (E) a drain throw (a Buf too
//  small for the burst — events LOST) drops everything; (F) arming lands
//  BEFORE the compute, so a write DURING compute is not missed; (G) the value
//  is free-form and untouched, and two keys share one repo bucket.
"use strict";

const { eq, ok } = require("./lib/assert.js");
//  DIS-054 isolated-clone require: derive the be/ code dir from this script's
//  own path (`<be>/test/cache.js` → `<be>`), fall back to be-relative.
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const cache = _req("shared/cache.js");

const TMP = io.getenv("TMP") || "/tmp";
const base = TMP + "/bro043-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
//  P (parent repo), P/C (a nested repo — a `.be` FILE is the boundary marker
//  classify.wtWalk detects), S (a sibling).  Plain dirs are enough: the cache
//  keys on `repo.wt` and never opens a store.
const P = base + "/p", C = P + "/c", S = base + "/s";
io.mkdir(P + "/src"); io.mkdir(C); io.mkdir(S);
function write(p, s) {
  const u = utf8.Encode(s), b = io.buf(u.length + 8); b.feed(u);
  const fd = io.open(p, "c"); io.writeAll(fd, b); io.close(fd);
}
write(C + "/.be", "");                      // C is its own repo boundary
const repo = (wt) => ({ wt: wt });

//  A counting compute: `calls[tag]` is how many times the value was rebuilt.
const calls = {};
function comp(tag, val) {
  return function () { calls[tag] = (calls[tag] || 0) + 1; return val || { tag: tag }; };
}

//  --- A: no watcher ⇒ the cache does not exist ⇒ every read recomputes ---
(function () {
  const real = fsw.init;
  fsw.init = function () { throw "EMFILE"; };
  try {
    eq(cache.start(base), false, "A: a failed watcher start reports false");
    eq(cache.stats().live, false, "A: the cache object stays null");
    cache.take(repo(P), "k", comp("A"));
    cache.take(repo(P), "k", comp("A"));
    eq(calls.A, 2, "A: EVERY read recomputes with no watcher");
    eq(cache.stats().hits, 0, "A: nothing is ever a hit");
  } finally { fsw.init = real; cache.stop(); }
})();

//  --- B: miss, then hit ---------------------------------------------------
eq(cache.start(base), true, "B: the watcher starts");
(function () {
  const v1 = cache.take(repo(P), "quad", comp("B", { n: 1 }));
  const v2 = cache.take(repo(P), "quad", comp("B", { n: 2 }));
  eq(calls.B, 1, "B: the second read does not recompute");
  eq(v1.n, 1, "B: the miss returns its own value");
  eq(v2.n, 1, "B: the hit returns the STORED value");
  ok(cache.stats().dirs > 0, "B: the miss armed real dirs");
  ok(cache.stats().hits === 1 && cache.stats().misses === 1, "B: stats count both");
})();

//  --- G: free-form value, several keys, one repo bucket -------------------
(function () {
  const marker = { rows: [1, 2, 3], deep: { x: "y" } };
  const got = cache.take(repo(P), "other", comp("G", marker));
  eq(got, marker, "G: the value crosses untouched (same object)");
  eq(cache.take(repo(P), "other", comp("G")), marker, "G: 2nd key hits too");
  eq(cache.take(repo(P), "quad", comp("B", { n: 9 })).n, 1, "G: keys are independent");
  eq(calls.G, 1, "G: only the first read of a key computes");
})();

//  --- C: a write drops the repo AND its ancestors, not siblings/descendants
(function () {
  cache.take(repo(C), "quad", comp("C-child"));
  cache.take(repo(S), "quad", comp("C-side"));
  eq(calls["C-child"], 1, "C: child computed once");
  write(C + "/touched.txt", "x\n");
  //  The next take drains the event first.
  cache.take(repo(C), "quad", comp("C-child"));
  eq(calls["C-child"], 2, "C: the TOUCHED repo recomputes");
  cache.take(repo(P), "quad", comp("B"));
  eq(calls.B, 2, "C: its ANCESTOR recomputes (a parent embeds its subs)");
  cache.take(repo(S), "quad", comp("C-side"));
  eq(calls["C-side"], 1, "C: a SIBLING keeps its bucket");
  //  ... and a write in the PARENT leaves the CHILD alone.
  write(P + "/src/p.txt", "y\n");
  cache.take(repo(P), "quad", comp("B"));
  eq(calls.B, 3, "C: the parent recomputes after its own write");
  cache.take(repo(C), "quad", comp("C-child"));
  eq(calls["C-child"], 2, "C: the DESCENDANT keeps its bucket");
})();

//  --- F: arming lands BEFORE the compute ---------------------------------
//  A write that happens DURING the compute must still be seen: if the arm ran
//  after, the entry would be born stale and the next read would hit it.
(function () {
  const F = base + "/f";
  io.mkdir(F);
  calls.F = 0;
  cache.take(repo(F), "quad", function () {
    calls.F++;
    write(F + "/mid.txt", "during\n");               // a racing writer
    return { mid: true };
  });
  eq(calls.F, 1, "F: the cold read computed");
  cache.take(repo(F), "quad", function () { calls.F++; return {}; });
  eq(calls.F, 2, "F: a write DURING the compute is not missed");
})();

//  --- D: an OVERFLOW record drops everything -----------------------------
(function () {
  cache.take(repo(P), "d", comp("D-p"));
  cache.take(repo(S), "d", comp("D-s"));
  eq(calls["D-p"], 1, "D: warm");
  const rd = fsw.records, dr = fsw.drain;
  fsw.drain = function () { return 1; };
  fsw.records = function () { return [{ wd: fsw.OVERFLOW, name: "" }]; };
  try { cache.take(repo(P), "d", comp("D-p")); }
  finally { fsw.records = rd; fsw.drain = dr; }
  eq(calls["D-p"], 2, "D: overflow dropped the repo");
  cache.take(repo(S), "d", comp("D-s"));
  eq(calls["D-s"], 2, "D: overflow dropped EVERY repo, not one dir");
})();

//  --- E: a drain throw (the burst did not fit — events LOST) → dropAll ----
(function () {
  cache.take(repo(P), "e", comp("E-p"));
  cache.take(repo(S), "e", comp("E-s"));
  eq(calls["E-p"], 1, "E: warm");
  const dr = fsw.drain;
  fsw.drain = function () { throw "NOROOM"; };
  try { cache.take(repo(P), "e", comp("E-p")); }
  finally { fsw.drain = dr; }
  eq(calls["E-p"], 2, "E: a lost burst drops the repo");
  cache.take(repo(S), "e", comp("E-s"));
  eq(calls["E-s"], 2, "E: a lost burst drops every repo");
})();

//  --- H: the SINGLETON trap — `jsrc` is a symlink to `.`, so the same file
//  loads twice under two paths.  A second module instance MUST be the same
//  cache, else it silently no-ops (`live=true, hits=0` reading like a win).
(function () {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  const d = self ? self.slice(0, self.lastIndexOf("/test/")) : "";
  if (!d || d === self) return;                      // be-relative fallback: skip
  let twin = null;
  try { twin = require(d + "/jsrc/shared/cache.js"); } catch (e) { return; }
  if (twin === cache) return;                        // no jsrc symlink here
  ok(twin !== cache, "H: the twin really is a SECOND module instance");
  eq(twin.stats().live, cache.stats().live, "H: both see one liveness");
  const before = cache.stats().misses;
  twin.take(repo(P), "h", comp("H"));
  cache.take(repo(P), "h", comp("H"));
  eq(calls.H, 1, "H: a take through EITHER instance hits the one record");
  eq(cache.stats().misses, before + 1, "H: and bumps the one counter set");
})();

//  --- stop(): the cache is gone, reads recompute again -------------------
cache.stop();
eq(cache.stats().live, false, "stop: the cache object is null again");
cache.take(repo(P), "z", comp("Z"));
cache.take(repo(P), "z", comp("Z"));
eq(calls.Z, 2, "stop: every read recomputes once the watcher is gone");

io.rmdir(base, true);
io.log("PASS cache.js");
