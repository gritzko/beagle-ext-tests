//  test/mill/pack.js — TEST-004: the treadmill for `git.pack(fd, buf, shard,
//  opts)` itself ([JAB-020]'s one-call binding, live in jab since
//  2026-07-27).  Fetches <uri> with git, repacks the resulting pack THROUGH
//  THE BINDING, and asserts what a repack must satisfy: every object
//  accounted for, every input byte consumed, the logs under the cap, and a
//  PIPE run byte-identical to a FILE run ([KEEP-006]'s "streaming changes
//  nothing", made a standing test instead of a one-off measurement).
//
//  This is the script the kernel is for: 6.33 GB in, 11,690,992 objects, no
//  pack bytes in the JS heap at any point.
//
//  Run: jab test/mill/pack.js <uri> [--cap BYTES] [--mode file|pipe|both]
"use strict";

const m = require("./lib.js");

const SYNOPSIS =
  "pack.js — repack <uri>'s pack through git.pack and check it (TEST-004)\n" +
  "\n" +
  "usage: jab test/mill/pack.js <uri> [options]\n" +
  "\n" +
  "  --cap BYTES      per-log cap handed to git.pack (default: the binding's\n" +
  "                   own 2^31-1).  A small cap forces rotation, which is\n" +
  "                   what turns crossing OFS deltas into REF ones.\n" +
  "  --mode M         file | pipe | both (default both: the two runs must\n" +
  "                   produce identical logs)\n" +
  "  --buf BYTES      input buffer size (default 1 GiB, io.ram)\n" +
  "  --keep-repo D    reuse/keep the bare git clone at D (skips the fetch on\n" +
  "                   a re-run — a kernel fetch is ~20 minutes)";

const o = m.parseArgs(process.argv, "pack", SYNOPSIS);

//  wh128 index entries are 16 bytes; one per object plus the per-log run
//  headroom the binding adds on rotation.  Sized off the pack's own header
//  count, so a kernel pack asks for ~200 MB of MAP_NORESERVE and touches
//  only what it fills.
const IX_ENTRY = 16;
const IX_SLACK = 1.5;

function main() {
  m.need("git", "the pack under test is fetched with git");
  m.need("timeout", "the fetch runs under a ceiling");

  const GITURL = m.refUrl(o);
  const ROOT = m.scratchRoot(o.id);
  const REPO = o.keepRepo || (ROOT + "/src.git");

  m.say("=== mill pack: " + o.uri);
  m.say("    jab      " + m.JAB_BIN);
  m.say("    source   " + GITURL);
  m.say("    scratch  " + ROOT + (o.keep ? "  (kept)" : ""));
  m.say("");

  let failures = 0;
  const fail = function (msg) { failures++; m.say("FAIL  " + msg); };
  const pass = function (msg) { m.say("PASS  " + msg); };

  try {
    //  ---- 1. get a pack ---------------------------------------------------
    //  `--bare` + `repack -ad` so the whole history is ONE pack: the
    //  binding takes a single stream, exactly as a fetch would hand it one.
    let have = false;
    try { io.stat(REPO + "/objects"); have = true; } catch (e) {}
    if (!have) {
      m.say("--- git clone --bare " + GITURL + " ---");
      m.must("git clone", m.git(["clone", "--bare", "--quiet", GITURL, REPO],
                                { timeout: o.timeout, tee: true }));
    } else m.say("--- reusing the bare clone at " + REPO + " ---");

    let packs = listPacks(REPO);
    //  One pack or nothing to feed: a fetch hands the binding a single
    //  stream.  A local clone hardlinks the source's pack, so the usual
    //  case costs nothing — only a multi-pack source pays for the repack.
    if (packs.length !== 1) {
      m.say("    " + packs.length + " packs — `git repack -adq` to get one");
      m.must("git repack", m.git(["-C", REPO, "repack", "-adq"], { timeout: o.timeout }));
      packs = listPacks(REPO);
    }
    if (packs.length !== 1) m.die("expected exactly one pack in " + REPO +
                                  ", found " + packs.length + " after `git repack -adq`");
    const PACK = packs[0];
    const packSize = io.stat(PACK).size;
    m.say("    pack     " + PACK);
    m.say("    size     " + m.hb(packSize));

    //  git's own object count for the pack — the oracle for `stats.objects`.
    //  `count-objects -v` prints ONE line; `verify-pack -v` would print one
    //  per object (11.7M lines, ~1.4 GB, straight into this JS heap).
    const co = m.must("git count-objects", m.git(["-C", REPO, "count-objects", "-v"],
                                                 { timeout: o.timeout }));
    let gitObjects = 0;
    const clines = co.out.split("\n");
    for (let i = 0; i < clines.length; i++)
      if (clines[i].indexOf("in-pack:") === 0)
        gitObjects = Number(clines[i].slice(8).trim()) || 0;
    if (!gitObjects) m.die("`git count-objects -v` reported no in-pack objects:\n" + co.out);
    m.say("    objects  " + gitObjects + "  (git count-objects)");
    m.say("");

    //  ---- 2. repack it through the binding --------------------------------
    const modes = o.mode === "both" ? ["file", "pipe"] : [o.mode];
    const runs = {};
    for (let i = 0; i < modes.length; i++) {
      const mode = modes[i];
      const shard = ROOT + "/shard-" + mode;
      io.mkdir(shard);
      m.say("--- git.pack from a " + mode.toUpperCase() + " fd ---");
      const st = repack(PACK, shard, mode, gitObjects, o);
      runs[mode] = { stats: st.stats, shard: shard, wall: st.wall, rssKb: st.rssKb };
      report(st, packSize);

      //  ---- 3. the invariants --------------------------------------------
      const s = st.stats;
      if (s.objects === gitObjects) pass(mode + ": all " + gitObjects + " objects repacked");
      else fail(mode + ": repacked " + s.objects + " objects, git counts " + gitObjects);

      if (s.raw + s.ofs + s.ref === s.objects)
        pass(mode + ": raw+ofs+ref accounts for every object (" +
             s.raw + "+" + s.ofs + "+" + s.ref + ")");
      else fail(mode + ": raw+ofs+ref = " + (s.raw + s.ofs + s.ref) +
                ", objects = " + s.objects);

      //  The 20-byte sha1 trailer is verified, never repacked, so inBytes
      //  is the pack minus exactly that.
      if (s.inBytes === packSize - 20)
        pass(mode + ": consumed the whole pack (" + m.hb(s.inBytes) + " + the 20-byte trailer)");
      else fail(mode + ": consumed " + s.inBytes + " of " + (packSize - 20) + " pack bytes");

      const cap = o.cap || 2147483647;
      const biggest = biggestLog(shard);
      if (biggest <= cap) pass(mode + ": every log is under the " + m.hb(cap) + " cap (largest " + m.hb(biggest) + ")");
      else fail(mode + ": a log is " + m.hb(biggest) + ", over the " + m.hb(cap) + " cap");

      if (s.logs > 1 && s.ref === 0)
        fail(mode + ": " + s.logs + " logs but no REF delta — crossing bases were not re-anchored");
      else if (s.logs > 1)
        pass(mode + ": " + s.logs + " logs, " + s.ref + " crossing deltas re-anchored as REF");
    }

    //  ---- 4. FILE vs PIPE --------------------------------------------------
    if (runs.file && runs.pipe) {
      m.say("");
      m.say("--- FILE vs PIPE ---");
      //  KEEP-006: the call now lands `<ron60>.keeper.idx` runs beside the
      //  logs, and a run's NAME is a wall-clock ron60 — necessarily different
      //  between two runs.  Compare the logs by name, and the index runs
      //  pairwise in name (== age) order, so content still has to match.
      const kind = (dir, ext) => io.readdir(dir).filter((n) => n.endsWith(ext)).sort();
      const cmp = (an, bn) =>
        m.run("cmp", ["cmp", runs.file.shard + "/" + an,
                      runs.pipe.shard + "/" + bn], {}).code === 0;
      const fl = kind(runs.file.shard, ".keeper"), pl = kind(runs.pipe.shard, ".keeper");
      const fi = kind(runs.file.shard, ".keeper.idx"), pi = kind(runs.pipe.shard, ".keeper.idx");
      let bad = null;
      if (fl.length !== pl.length) bad = "log counts differ";
      else if (fi.length !== pi.length) bad = "index run counts differ";
      else {
        for (let i = 0; i < fl.length && !bad; i++)
          if (fl[i] !== pl[i] || !cmp(fl[i], pl[i])) bad = "log " + fl[i];
        for (let i = 0; i < fi.length && !bad; i++)
          if (!cmp(fi[i], pi[i])) bad = "index run " + fi[i] + " vs " + pi[i];
      }
      if (!bad) pass("the streamed run produced byte-identical logs and index runs");
      else fail("the streamed and mapped runs differ: " + bad);
      const a = runs.file.stats, b = runs.pipe.stats;
      if (JSON.stringify(a) === JSON.stringify(b)) pass("identical stats from both fds");
      else fail("stats differ:\n  file " + JSON.stringify(a) + "\n  pipe " + JSON.stringify(b));
    }
  } finally {
    if (o.keep) m.say("\nscratch kept: " + ROOT);
    else m.rmrf(ROOT, ROOT);
  }

  m.say("");
  if (failures) m.die(failures + " check(s) failed");
  m.say("=== mill pack OK ===");
}

//  One repack.  `mode` picks the fd: a plain file (the mapped-equivalent
//  path) or a PIPE off `cat` (what a socket looks like to the binding).
//  Both buffers come from io.ram — MAP_NORESERVE, lazily faulted, and NEVER
//  grown by the binding ([JAB-020] §Goals: allocation stays in JS).
function repack(pack, shard, mode, objects, o) {
  const buf = io.ram(o.buf);
  const index = io._ram(Math.ceil(objects * IX_SLACK) * IX_ENTRY + (1 << 20));
  let fd, child = null;
  if (mode === "pipe") {
    child = io.spawn("cat", ["cat", pack]);
    io.close(child.stdin);
    fd = child.stdout;
  } else fd = io.open(pack, "r");

  let steps = 0;
  const t0 = Date.now();
  const conf = { index: index, every: 250000,
                 onStep: function (s) {
                   steps++;
                   m.say("    … " + s.objects + " objects, " + m.hb(s.inBytes) +
                         " in, " + s.logs + " log(s)");
                 } };
  if (o.cap) conf.cap = o.cap;
  let stats = null, err = null;
  try { stats = git.pack(fd, buf, shard, conf); }
  catch (e) { err = String(e); }
  const wall = Date.now() - t0;
  try { io.close(fd); } catch (e) {}
  if (child) { try { io.reap(child.pid); } catch (e) {} }
  if (err) m.die("git.pack (" + mode + ") failed: " + err);
  //  Peak RSS of THIS process: the repack runs in-process, so our own
  //  VmHWM is the honest number — the whole point of the one-call binding.
  return { stats: stats, wall: wall, rssKb: m.peakRss(io.getpid()),
           steps: steps, buf: buf };
}

function report(st, packSize) {
  const s = st.stats, secs = st.wall / 1000;
  m.say("    stats    " + JSON.stringify(s));
  m.say("    wall     " + m.hms(st.wall) +
        (secs > 0 ? "  (" + m.hb(s.inBytes / secs) + "/s, " +
                    Math.round(s.objects / secs) + " obj/s)" : ""));
  m.say("    peak RSS " + m.hb(st.rssKb * 1024) + "  (this process)");
  m.say("    logs     " + s.logs + ", " + m.hb(s.outBytes) + " out, " +
        s.indexN + " index entries");
  m.say("    left in the buffer: " + (st.buf._idle - st.buf._data) +
        " bytes (the trailer)");
}

function listPacks(repo) {
  const out = [];
  let names = [];
  try { names = io.readdir(repo + "/objects/pack"); } catch (e) { return out; }
  for (let i = 0; i < names.length; i++) {
    const n = String(names[i].name || names[i]);
    if (n.length > 5 && n.slice(n.length - 5) === ".pack")
      out.push(repo + "/objects/pack/" + n);
  }
  return out;
}

function biggestLog(shard) {
  let max = 0;
  const names = io.readdir(shard);
  for (let i = 0; i < names.length; i++) {
    const n = names[i].name || names[i];
    if (String(n).indexOf(".keeper") < 0) continue;
    const sz = Number(io.stat(shard + "/" + n).size) || 0;
    if (sz > max) max = sz;
  }
  return max;
}

function isHex(s) {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (!((c >= 48 && c <= 57) || (c >= 97 && c <= 102))) return false;
  }
  return s.length > 0;
}

if (o !== null) main();
