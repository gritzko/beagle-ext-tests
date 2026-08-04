//  STATUS-019: shared/cache.js — the per-dir REV TREE, the universal fs change
//  witness.  Legs: (A) no watcher ⇒ no revs, every query is a fresh token so
//  every consumer recomputes; (B) a rev stands still while nothing happens;
//  (C) an event bumps its dir AND every ANCESTOR, never a sibling or a
//  descendant; (D) an `fsw.OVERFLOW` record bumps the ROOT (every spot moves);
//  (E) a drain throw (a Buf too small — events LOST) is the same fact;
//  (F) a write landing right after the query is not missed (arming lands on the
//  query, before the caller computes); (G) `bumpRoot` is the `R`/`r` gesture;
//  (H) the jsrc-symlink twin is ONE rev tree; (I) an unwatchable path never
//  hands out a stable rev.
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
const base = TMP + "/status019-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
//  P (a repo), P/src (a plain dir under it), P/c (a nested repo — a `.be` FILE
//  is the boundary marker classify.wtWalk detects), S (a sibling).
const P = base + "/p", SRC = P + "/src", C = P + "/c", S = base + "/s";
io.mkdir(SRC); io.mkdir(C); io.mkdir(S);
function write(p, s) {
  const u = utf8.Encode(s), b = io.buf(u.length + 8); b.feed(u);
  const fd = io.open(p, "c"); io.writeAll(fd, b); io.close(fd);
}
write(C + "/.be", "");                      // C is its own repo boundary

//  --- A: no watcher ⇒ no revs at all ⇒ every consumer recomputes ----------
(function () {
  const real = fsw.init;
  fsw.init = function () { throw "EMFILE"; };
  try {
    eq(cache.start(base), false, "A: a failed watcher start reports false");
    eq(cache.stats().live, false, "A: the rev tree stays null");
    const a = cache.rev(P), b = cache.rev(P);
    ok(a !== b, "A: with no watcher no two queries ever agree (all recompute)");
    eq(cache.stats().hits, 0, "A: nothing is ever a hit");
  } finally { fsw.init = real; cache.stop(); }
})();

//  --- B: a live rev stands still while nothing happens --------------------
eq(cache.start(base), true, "B: the watcher starts");
(function () {
  const r1 = cache.rev(P), r2 = cache.rev(P);
  eq(r1, r2, "B: the rev stands still with no event");
  ok(cache.stats().dirs > 0, "B: the first query ARMED real dirs");
  ok(cache.stats().misses === 1 && cache.stats().hits === 1,
     "B: stats count the first query as a miss, the re-ask as a hit");
})();

//  --- C: an event bumps its dir AND its ancestors, not siblings/descendants
(function () {
  const p0 = cache.rev(P), c0 = cache.rev(C), s0 = cache.rev(S), src0 = cache.rev(SRC);
  write(C + "/touched.txt", "x\n");
  const c1 = cache.rev(C);
  ok(c1 !== c0, "C: the TOUCHED dir's rev moved");
  ok(cache.rev(P) !== p0, "C: its ANCESTOR moved too");
  eq(cache.rev(S), s0, "C: a SIBLING tree keeps its rev");
  eq(cache.rev(SRC), src0, "C: an unrelated dir under the ancestor keeps its rev");
  //  ... and a write in the PARENT leaves the nested repo alone.
  const p1 = cache.rev(P), c2 = cache.rev(C);
  write(SRC + "/p.txt", "y\n");
  ok(cache.rev(SRC) !== src0, "C: the written dir moved");
  ok(cache.rev(P) !== p1, "C: the parent moved with it");
  eq(cache.rev(C), c2, "C: the DESCENDANT repo keeps its rev");
})();

//  --- F: a write landing AFTER the query is never missed ------------------
//  The query is what arms, so a writer racing the caller's compute still fires.
(function () {
  const F = base + "/f";
  io.mkdir(F);
  const f0 = cache.rev(F);                   // the query arms F
  write(F + "/mid.txt", "during\n");         // a racing writer
  ok(cache.rev(F) !== f0, "F: a write right after the query is not missed");
})();

//  --- D: an OVERFLOW record bumps the ROOT — every spot moves -------------
(function () {
  const p0 = cache.rev(P), s0 = cache.rev(S), c0 = cache.rev(C);
  const rd = fsw.records, dr = fsw.drain;
  let once = true;
  fsw.drain = function () { if (!once) return 0; once = false; return 1; };
  fsw.records = function () { return [{ wd: fsw.OVERFLOW, name: "" }]; };
  try { cache.poll(); } finally { fsw.records = rd; fsw.drain = dr; }
  ok(cache.rev(P) !== p0 && cache.rev(S) !== s0 && cache.rev(C) !== c0,
     "D: overflow moved EVERY rev, not one dir");
})();

//  --- E: a drain throw (the burst did not fit — events LOST) → root bump --
(function () {
  const p0 = cache.rev(P), s0 = cache.rev(S);
  const dr = fsw.drain;
  fsw.drain = function () { throw "NOROOM"; };
  try { cache.poll(); } finally { fsw.drain = dr; }
  ok(cache.rev(P) !== p0 && cache.rev(S) !== s0, "E: a lost burst moves every rev");
})();

//  --- G: bumpRoot — the pager's `R`/`r` "I do not trust this screen" ------
(function () {
  const p0 = cache.rev(P), s0 = cache.rev(S);
  cache.bumpRoot();
  ok(cache.rev(P) !== p0 && cache.rev(S) !== s0, "G: bumpRoot moves every rev");
})();

//  --- I: a path that cannot be watched never hands out a stable rev -------
(function () {
  const gone = base + "/nope";
  const a = cache.rev(gone), b = cache.rev(gone);
  ok(a !== b, "I: an unwatchable path always recomputes (ruling 4)");
})();

//  --- H: the SINGLETON trap — `jsrc` is a symlink to `.`, so the same file
//  loads twice under two paths.  A second module instance MUST be the same
//  rev tree, else it silently hands out its own revs and nothing invalidates.
(function () {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  const d = self ? self.slice(0, self.lastIndexOf("/test/")) : "";
  if (!d || d === self) return;                      // be-relative fallback: skip
  let twin = null;
  try { twin = require(d + "/jsrc/shared/cache.js"); } catch (e) { return; }
  if (twin === cache) return;                        // no jsrc symlink here
  ok(twin !== cache, "H: the twin really is a SECOND module instance");
  eq(twin.stats().live, cache.stats().live, "H: both see one liveness");
  eq(twin.rev(P), cache.rev(P), "H: both instances answer the ONE rev");
  const p0 = cache.rev(P);
  twin.bumpRoot();
  ok(cache.rev(P) !== p0, "H: a bump through EITHER instance moves the one tree");
})();

//  --- stop(): the tree is gone, every query recomputes again --------------
cache.stop();
eq(cache.stats().live, false, "stop: the rev tree is null again");
ok(cache.rev(P) !== cache.rev(P), "stop: no two queries agree once the watcher is gone");

io.rmdir(base, true);
io.log("PASS cache.js");
