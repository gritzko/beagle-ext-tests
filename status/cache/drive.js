//  STATUS-019 repro driver — the REAL path: ONE resident process that runs the
//  REAL `status` verb through core/loop.js (exactly what the pager's driveSpell
//  does), with the shared/cache.js REV TREE live and status.js keeping its own
//  {rows, state, rev} memo.  The work measure is IMPLEMENTATION-BLIND: the
//  CFOLD-001 `JAB_STATS` object-read counter (the same one test/status/cfold
//  asserts on).  A memo HIT must read ~0 objects and render BYTE-IDENTICAL
//  output; a write under a repo must move its rev and its ANCESTORS' while a
//  sibling's stands still; a track tip that moved with NO fs event (so no rev
//  moved at all) must still recompute through the `state` fingerprint.
//  args: <fixture root> <jsrc dir>   (the jsrc the fixture's own verbs load
//  from — the driver MUST share those module instances, so it requires through
//  the very same path, and hands loop.js that root as its process.argv[1]).
"use strict";

//  MODE "store" runs the two-wt store axis in a FRESH process: a `?branch`
//  track resolve is POISONED for every later repo once another repo's status
//  ran in the same process (pre-existing, unrelated to the cache — proposed as
//  its own ticket), so the leg cannot share a process with the forest legs.
const ROOT = args[0], JSRC = args[1], JAB = args[2], MODE = args[3] || "main";
process.argv[1] = JSRC + "/main.js";
const loop  = require(JSRC + "/core/loop.js");
const cache = require(JSRC + "/shared/cache.js");
//  The object-read counter, read STRAIGHT off the module the verbs bump (never
//  a scraped log line) — one instance, so a miscount cannot masquerade as a win.
const stats = require(JSRC + "/shared/util/stats.js");

const TOP = ROOT + "/top", SUB = TOP + "/sub", SIDE = ROOT + "/side";
const WTA = ROOT + "/A", WTB = ROOT + "/B";

//  BRO-043 §Blockers: `jsrc` is a symlink to `.`, so the SAME file loads twice
//  under two paths.  The state lives on one globalThis slot, so both instances
//  MUST be the same cache — else `live=true, hits=0` reads like a working cache.
const cache2 = require(JSRC + "/shared/../shared/cache.js");
//  STATUS-019: `rev` on a spot the caller last saw at the same value is what a
//  consumer's memo serves — hits/misses below are that rev-level tally.

let fails = 0;
function ok(cond, msg) {
  if (!cond) { fails++; io.log("FAIL " + msg); } else io.log("ok   " + msg);
}

//  Run the REAL verb in-process, capturing fd 1 (the driveSpell hook).
function spell(argv) {
  const oWriteAll = io.writeAll, oWrite = io.write;
  const outs = [];
  io.writeAll = function (fd, b) {
    if (fd === 1) { outs.push(b.data().slice()); return; }
    if (fd === 2) return;
    return oWriteAll(fd, b);
  };
  io.write = function (fd, b) { if (fd === 2) return; return oWrite(fd, b); };
  try { loop.cli(["jab", "loop.js"].concat(argv), { reentry: true }); }
  finally { io.writeAll = oWriteAll; io.write = oWrite; }
  let n = 0; for (const c of outs) n += c.length;
  const all = new Uint8Array(n); let o = 0;
  for (const c of outs) { all.set(c, o); o += c.length; }
  return utf8.Decode(all);
}

let last = 0, lastHits = 0, lastMisses = 0;   // the counters are CUMULATIVE
function status(dir, arg) {
  io.chdir(dir);
  const text = spell(arg ? ["status", arg, "--plain"] : ["status", "--plain"]);
  const c = cache.stats();
  const d = { text: text, work: stats.counts.obj - last,
              hits: c.hits - lastHits, misses: c.misses - lastMisses };
  last = stats.counts.obj; lastHits = c.hits; lastMisses = c.misses;
  return d;
}
function write(p, s) {
  const u = utf8.Encode(s), b = io.buf(u.length + 8); b.feed(u);
  const fd = io.open(p, "c"); io.writeAll(fd, b); io.close(fd);
}
//  Run a jab command in ANOTHER process, in `dir` — the cross-process shape.
function run(argv, dir) {
  const here = io.cwd();
  io.chdir(dir);
  try {
    const p = io.spawn(argv[0], argv);
    io.close(p.stdin);
    const b = io.ram(1 << 18);
    while (io.read(p.stdout, b) > 0) {}
    io.close(p.stdout);
    return io.reap(p.pid);
  } finally { io.chdir(here); }
}

ok(stats.ON, "JAB_STATS is on (the object-read counter is live)");

if (MODE === "store") {
  //  --- 7. a moved TRACK TIP misses through `state` with NO fs event -------
  storeAxis();
  io.log(fails === 0 ? "PASS" : ("FAILED " + fails));
  if (fails) throw "BRO043FAIL";
} else {

//  --- 0. the singleton is ONE cache, whatever path it was required through --
ok(cache2.stats === cache.stats || cache2.stats().live === cache.stats().live,
   "both module instances share the one globalThis record");

//  --- 1. with NO watcher there are no revs: every read recomputes ----------
//  (leg g — the safety property, asserted BEFORE anything is warm.)
const n1 = status(TOP), n2 = status(TOP);
ok(n1.hits === 0 && n1.misses === 0 && n2.hits === 0 && n2.misses === 0,
   "watcher-less: no rev is ever handed out");
ok(n1.work === n2.work && n1.work > 0,
   "watcher-less: every read pays the same full work (" + n1.work + ")");
const UNCACHED = n1.work, UNCACHED_TEXT = n1.text;

ok(cache.start(ROOT) === true, "watcher started (revs exist at all)");

//  --- 2. hit vs miss: byte-identical output, ~0 objects read ---------------
const a1 = status(TOP);
const a2 = status(TOP);
ok(a1.misses === 1 && a1.hits === 0, "first status MISSES");
ok(a2.hits === 1 && a2.misses === 0, "re-fire finds the rev STANDING STILL");
ok(a1.work === UNCACHED, "a MISS pays exactly the uncached work (" + a1.work + ")");
//  THE BAR (ticket §TODOs): a hit reads ~0 objects — only the `state`
//  fingerprint's refs.  The first (quad-level) attempt read 2240 of 2425.
ok(a2.work <= 8, "a HIT reads ~0 objects: " + a2.work + " (miss " + a1.work + ")");
ok(a2.text === a1.text && a1.text === UNCACHED_TEXT && a1.text.length > 0,
   "hit, miss and uncached renders are BYTE-IDENTICAL");
const MISS_TOP = a1.work, HIT_TOP = a2.work;

//  --- 3. the other two buckets --------------------------------------------
const s1 = status(SUB), d1 = status(SIDE);
ok(s1.misses === 1 && d1.misses === 1, "sub + sibling each compute once (" +
   s1.work + "," + d1.work + ")");
const MISS_SUB = s1.work, MISS_SIDE = d1.work;
const s1b = status(SUB), d1b = status(SIDE);
ok(s1b.hits === 1 && s1b.work <= 8, "sub re-fire hits its memo (" + s1b.work + ")");
ok(d1b.hits === 1 && d1b.work <= 8, "sibling re-fire hits its memo (" + d1b.work + ")");
const HIT_SUB = s1b.work, HIT_SIDE = d1b.work;

//  --- 4. a write under SUB moves SUB *and* its ancestor TOP, not SIDE ------
write(SUB + "/fresh.txt", "new\n");
const s2 = status(SUB), a3 = status(TOP), d2 = status(SIDE);
ok(s2.misses === 1, "touched repo recomputes (" + s2.work + ")");
ok(s2.text.indexOf("fresh.txt") >= 0, "recompute SEES the new file");
ok(a3.misses === 1 && a3.work === MISS_TOP, "the ANCESTOR spot moved too (" + a3.work + ")");
ok(d2.hits === 1 && d2.work === HIT_SIDE, "the SIBLING rev stood still (" + d2.work + ")");

//  --- 5. a write under TOP moves TOP, not its descendant SUB --------------
write(TOP + "/top-new.txt", "t\n");
const a4 = status(TOP), s3 = status(SUB);
ok(a4.misses === 1 && a4.work === MISS_TOP, "top recomputes after its own write");
ok(s3.hits === 1 && s3.work === HIT_SUB, "the DESCENDANT sub rev stood still");

//  --- 6. a SCOPED read memoizes nothing and recomputes ---------------------
const p1 = status(TOP, "src"), p2 = status(TOP, "src");
ok(p1.hits === 0 && p1.misses === 0 && p2.hits === 0 && p2.misses === 0 &&
   p1.work === p2.work && p1.work > HIT_TOP,
   "scoped `status src` memoizes NOTHING (" + p1.work + "," + p2.work + ")");

//  --- 8. a root bump (overflow, or the pager's `R`) moves every rev --------
status(TOP);                                   // warm
cache.bumpRoot();
const o1 = status(TOP);
ok(o1.misses === 1 && o1.work === MISS_TOP, "bumpRoot forces a recompute");

const st = cache.stats();
io.log("cache: hits=" + st.hits + " misses=" + st.misses + " drops=" + st.drops +
       " dirs=" + st.dirs);
ok(st.hits > 0 && st.misses > 0, "rev stats record both standstills and moves");
ok(st.rev > 0 && st.dirs > 0, "the rev tree armed dirs and its counter moved");

//  --- 9. with the watcher gone there are no revs again ---------------------
cache.stop();
const z1 = status(TOP), z2 = status(TOP);
ok(z1.work === MISS_TOP && z2.work === MISS_TOP,
   "watcher-less = every read recomputes (" + z1.work + "," + z2.work + ")");
ok(z1.text === z2.text, "and still renders identically");

}

//  Leg 7 — the STORE axis, in its OWN process (see MODE above).
//  A and B are two worktrees on ONE store, both tracking its `?trunk`.  The
//  bare `post` (a PUSH) runs in ANOTHER PROCESS and rewrites the shared
//  `<shard>/refs` tip — no file under B changes, so the watcher sees nothing
//  and only the `state` fingerprint can tell.
function storeAxis() {
  ok(cache.start(ROOT) === true, "watcher started");
  const c1 = status(WTB), c2 = status(WTB);
  ok(c1.misses === 1 && c2.hits === 1, "B warms (" + c1.work + " -> " + c2.work + ")");
  ok(c2.work <= 8, "B's hit reads ~0 objects (" + c2.work + ")");
  ok(c2.text.indexOf("behind") < 0, "B is level with trunk before the push");
  ok(run([JAB, "post"], WTA).code === 0, "A pushes its commit to the shared store");
  const c3 = status(WTB);
  //  STATUS-019: no file under B changed, so B's REV stands still (a rev-level
  //  hit) — only the `state` fingerprint can force the recompute, and the
  //  object-read counter is what proves it happened.
  ok(c3.work >= c1.work,
     "a track tip moved with NO fs event still RECOMPUTES via `state` (" +
     c3.work + " vs " + c1.work + ")");
  ok(c3.text !== c2.text && c3.text.indexOf("behind 1") >= 0,
     "the recompute shows the moved track (behind 1)");
  const c4 = status(WTB);
  ok(c4.work <= 8 && c4.text === c3.text, "and the new state re-warms, identically");
  cache.stop();
}

io.log(fails === 0 ? "PASS" : ("FAILED " + fails));
if (fails) throw "BRO043FAIL";
