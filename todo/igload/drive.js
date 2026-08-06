//  BE-064 repro driver — the REAL `todo` board render through core/loop.js
//  (the rowcache driver's shape), counting the DUPLICATE CALL CHAIN behind it:
//  `ignore.load` and `gitmodules.paths` are called PER ROOT, and a render that
//  calls either one TWICE for the same root did the same read twice.
//  cache.js's `arm()` walks a wt with a freshly loaded matcher and publishes the
//  walk (TODO-006); classifyMerge then re-loaded that very matcher and
//  re-parsed that very `.gitmodules` microseconds later, and recurse.walk parsed
//  it a third time.  So the measure is implementation-blind: the WORST REPEAT
//  COUNT of one argument, over one board render.
//    * with a LIVE watcher no root may be read twice (RED before BE-064: 2);
//    * the bytes must equal the watcher-OFF render's bytes, exactly;
//    * with no watcher the counts stay at today's path — nothing memoised.
//  args: <project root> <jsrc dir>   (the driver MUST share the verbs' module
//  instances, so it requires through the very same path loop.js resolves).
"use strict";

const ROOT = args[0], JSRC = args[1];
process.argv[1] = JSRC + "/main.js";
const loop  = require(JSRC + "/core/loop.js");
const cache = require(JSRC + "/shared/cache.js");
//  THE two readers, wrapped where every caller reaches them (one instance).
const ignorelib  = require(JSRC + "/shared/util/ignore.js");
const gitmodules = require(JSRC + "/shared/gitmodules.js");

let tally = {};                       // "fn" -> { arg -> calls }
function count(fn, arg) {
  const m = tally[fn] || (tally[fn] = {});
  const k = String(arg);
  m[k] = (m[k] || 0) + 1;
}
const oLoad = ignorelib.load;
ignorelib.load = function (r) { count("ignore.load", r); return oLoad.apply(this, arguments); };
const oPaths = gitmodules.paths;
gitmodules.paths = function (r) { count("gitmodules.paths", r); return oPaths.apply(this, arguments); };

//  calls, distinct args, and the WORST repeat — the whole verdict in one row.
function score(fn) {
  const m = tally[fn] || {};
  let calls = 0, distinct = 0, worst = 0, who = "";
  for (const k in m) {
    calls += m[k]; distinct++;
    if (m[k] > worst) { worst = m[k]; who = k; }
  }
  return { calls: calls, distinct: distinct, worst: worst, who: who };
}
function show(fn) {
  const s = score(fn);
  return fn + " " + s.calls + " calls / " + s.distinct + " roots, worst " +
         s.worst + "x" + (s.worst > 1 ? " (" + s.who + ")" : "");
}

let fails = 0;
function ok(cond, msg) {
  if (!cond) { fails++; io.log("FAIL " + msg); } else io.log("ok   " + msg);
}

//  Run the REAL verb in-process, capturing fd 1 (the driveSpell hook).
function spellRaw(argv) {
  const oWriteAll = io.writeAll, oWrite = io.write;
  const outs = [];
  io.writeAll = function (fd, b) {
    if (fd === 1) { outs.push(b.data().slice()); return; }
    if (fd === 2) return;
    return oWriteAll(fd, b);
  };
  io.write = function (fd, b) {
    if (fd === 1) { const d = b.data().slice(); outs.push(d); return d.length; }
    if (fd === 2) return;
    return oWrite(fd, b);
  };
  try { loop.cli(["jab", "loop.js"].concat(argv), { reentry: true }); }
  finally { io.writeAll = oWriteAll; io.write = oWrite; }
  let n = 0; for (const c of outs) n += c.length;
  const all = new Uint8Array(n); let o = 0;
  for (const c of outs) { all.set(c, o); o += c.length; }
  return all;
}
function board() {
  io.chdir(ROOT);
  tally = {};                          // ONE render's worth of calls
  return spellRaw(["todo", "--tlv"]);
}
function same(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

//  --- 1. no watcher: today's path, unmemoised ------------------------------
const off1 = board();
const offIg = score("ignore.load"), offGm = score("gitmodules.paths");
io.log("     watcher-off: " + show("ignore.load") + "; " + show("gitmodules.paths"));
ok(off1.length > 0, "the board renders (" + off1.length + " tlv bytes)");
ok(offIg.calls > 0 && offGm.calls > 0,
   "watcher-off reads both files (nothing is memoised without a witness)");

//  --- 2. LIVE watcher: the arming walk hands its matcher + subs down --------
ok(cache.start(ROOT) === true, "watcher started (the rev tree exists)");
const on1 = board();
const onIg = score("ignore.load"), onGm = score("gitmodules.paths");
io.log("     watcher-on:  " + show("ignore.load") + "; " + show("gitmodules.paths"));
ok(onIg.worst === 1,
   "no root's ignore matcher is loaded twice in one render (worst " +
   onIg.worst + "x, " + onIg.calls + " calls / " + onIg.distinct + " roots)");
ok(onGm.worst === 1,
   "no root's .gitmodules is parsed twice in one render (worst " +
   onGm.worst + "x, " + onGm.calls + " calls / " + onGm.distinct + " roots)");
//  The watcher legitimately arms (and so reads) MORE roots than a bare render
//  ever visits — topic dirs included; what it must never do is parse one repo's
//  `.gitmodules` more often than the watcher-less path already did.
ok(onGm.calls <= offGm.calls,
   "…parsing no more `.gitmodules` than the watcher-less render (" +
   onGm.calls + " vs " + offGm.calls + ")");
//  THE behaviour gate: a changed count is the goal, a changed byte is a bug.
ok(same(on1, off1), "the armed render is BYTE-IDENTICAL to the watcher-off one");

//  --- 3. the re-fire: a warm board re-reads neither file --------------------
const on2 = board();
const on2Ig = score("ignore.load"), on2Gm = score("gitmodules.paths");
io.log("     re-fire:     " + show("ignore.load") + "; " + show("gitmodules.paths"));
ok(on2Ig.worst <= 1 && on2Gm.worst <= 1,
   "the re-fire reads no root twice either (" + on2Ig.calls + "/" + on2Gm.calls + " calls)");
ok(same(on2, on1), "…and renders the very same bytes");

//  --- 4. degrade: with the watcher gone the old path must be intact ---------
cache.stop();
const off2 = board();
const off2Ig = score("ignore.load"), off2Gm = score("gitmodules.paths");
io.log("     watcher-off: " + show("ignore.load") + "; " + show("gitmodules.paths"));
ok(off2Ig.calls === offIg.calls && off2Gm.calls === offGm.calls,
   "a stopped watcher recomputes exactly as before it ever started (" +
   off2Ig.calls + "/" + off2Gm.calls + " vs " + offIg.calls + "/" + offGm.calls + ")");
ok(same(off2, off1), "…rendering the same bytes still");

io.log(fails === 0 ? "PASS" : ("FAILED " + fails));
if (fails) throw "BE064FAIL";
