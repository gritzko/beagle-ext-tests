//  test/mill/clone.js — TEST-004: ONE full `jab get <uri>` clone, measured.
//  The end-to-end half of the treadmill ([JAB-020]: "verify through a real
//  `jab get` of a large repo, not a unit probe"): wall clock, peak RSS of
//  the jab doing the ingest, store bytes, worktree files — and the tip
//  checked against git's view of the same repo.
//
//  This drives the CLI, so it measures whatever the clone path currently
//  does.  Until [JAB-020] routes `get` through `git.pack`, that is the
//  per-object JS loop — which is the baseline the conversion has to beat.
//  pack.js exercises the binding itself.
//
//  Run: jab test/mill/clone.js <uri> [--ref-uri U] [--ref-clone] [--keep]
"use strict";

const m = require("./lib.js");

const SYNOPSIS =
  "clone.js — measure one `jab get <uri>` clone (TEST-004)\n" +
  "\n" +
  "usage: jab test/mill/clone.js <uri> [options]\n" +
  "\n" +
  "  --ref-clone      also `git clone` the repo and rsync-compare the trees\n" +
  "                   (doubles the disk and the wall clock; without it the\n" +
  "                    oracle is a cheap `git ls-remote` tip check)";

const o = m.parseArgs(process.argv, "clone", SYNOPSIS);

function main() {
  m.need("git", "the treadmill's oracle is git itself");
  m.need("timeout", "every step runs under a per-step ceiling");
  if (o.refClone) m.need("rsync", "--ref-clone compares the trees with rsync -rlcni");

  const GITURL = m.refUrl(o);
  const ROOT = m.scratchRoot(o.id);
  const WT = ROOT + "/be";
  const REF = ROOT + "/git";

  //  --serve: clone from a local `git upload-pack` over http (this box has
  //  no sshd, and a bare git path is not a remote); the oracle is unchanged.
  const server = o.serve ? m.serveGit(GITURL) : null;
  const SRC = server ? server.uri : o.uri;

  m.say("=== mill clone: " + o.uri);
  if (server) m.say("    serving  " + GITURL + " at " + server.uri);
  m.say("    jab      " + m.JAB_BIN);
  m.say("    oracle   " + GITURL);
  m.say("    scratch  " + ROOT + (o.keep ? "  (kept)" : ""));
  m.say("");

  let failures = 0;
  try {
    m.plantShard(ROOT, m.beRoot());
    m.shieldWt(WT);

    //  ---- 1. the measured clone -------------------------------------------
    m.say("--- jab get " + SRC + " ---");
    const g = m.run(m.JAB_BIN, [m.JAB_BIN, "get", SRC],
                    { cwd: WT, timeout: o.timeout, tee: true, rss: true });

    const storeBytes = m.duBytes(WT + "/.be");
    m.say("");
    m.say("--- clone stats ---");
    m.say("    wall       " + m.hms(g.wall));
    //  Peak RSS of the ingesting jab: pre-[JAB-020] the pack crosses the JS
    //  heap, so this is the number the one-call binding must flatten.
    m.say("    peak RSS   " + (g.rssKb ? m.hb(g.rssKb * 1024) : "(unavailable)"));
    m.say("    store      " + m.hb(storeBytes) + "  in .be/");

    //  A failed clone still reports its measurements — a baseline run
    //  against a repo the current path cannot ingest is a RESULT, not a
    //  reason to throw the numbers away ([KEEP-006]: https buffers the
    //  whole body, a kernel-sized log exceeds the 2 GiB mmap cap).
    if (g.timedOut) { failures++; m.say("FAIL  jab get timed out after " + o.timeout + "s"); }
    else if (g.code !== 0) { failures++; m.say("FAIL  jab get exit " + g.code); }
    else {
      const files = m.wtFiles(WT);
      m.say("    worktree   " + files + " files");
      m.say("");
      if (o.refClone) failures += fullOracle(GITURL, REF, WT, files, o, g);
      else failures += tipOracle(GITURL, WT, o);
    }
  } finally {
    if (server) server.stop();
    if (o.keep) m.say("\nscratch kept: " + ROOT);
    else m.rmrf(ROOT, ROOT);
  }

  m.say("");
  if (failures) m.die(failures + " check(s) failed");
  m.say("=== mill clone OK ===");
}

//  The full oracle: clone with git and rsync-compare the two worktrees.
//  git's own wall/peak-RSS are reported beside jab's — same repo, same
//  transport, same box, so the pair IS the git-vs-beagle comparison.
function fullOracle(url, ref, wt, files, o, jab) {
  m.say("--- git clone (full oracle) ---");
  const g = m.must("git clone", m.git(["clone", "--quiet", "--recurse-submodules", url, ref],
                                      { timeout: o.timeout, tee: true, rss: true }));
  m.say("");
  m.say("--- git vs beagle ---");
  m.say("    git    " + m.pad(m.hms(g.wall), 10) +
        (g.rssKb ? m.hb(g.rssKb * 1024) + " peak" : ""));
  m.say("    jab    " + m.pad(m.hms(jab.wall), 10) +
        (jab.rssKb ? m.hb(jab.rssKb * 1024) + " peak" : ""));
  if (g.wall > 0)
    m.say("    ratio  " + (jab.wall / g.wall).toFixed(2) + "x  (jab / git wall)");
  m.say("");
  const diffs = m.treeDiff(ref, wt);
  if (diffs.length === 0) { m.say("PASS  worktrees identical (" + files + " files)"); return 0; }
  m.say("FAIL  " + diffs.length + " tree differences:");
  for (let i = 0; i < diffs.length && i < 20; i++) m.say("      " + diffs[i]);
  return 1;
}

//  The cheap oracle: git's HEAD sha vs the tip hashlet `jab log` shows.  A
//  PREFIX match — jab prints 8 hex where git prints 40.
function tipOracle(url, wt, o) {
  m.say("--- tip check (git ls-remote HEAD) ---");
  const ls = m.must("git ls-remote", m.git(["ls-remote", url, "HEAD"], { timeout: o.timeout }));
  const remote = ls.out.split("\t")[0].trim();
  const log = m.run(m.JAB_BIN, [m.JAB_BIN, "log"], { cwd: wt, timeout: o.timeout });
  if (log.code !== 0) m.die("jab log failed (exit " + log.code + ")");
  const tip = firstHashlet(log.out);
  if (!tip) m.die("cannot read a tip hashlet out of `jab log`:\n" + log.out.slice(0, 400));
  m.say("    git    " + remote);
  m.say("    jab    " + tip);
  if (remote.indexOf(tip) === 0) { m.say("PASS  tip matches git's HEAD"); return 0; }
  m.say("FAIL  tip does not match git's HEAD");
  return 1;
}

//  `jab log` prints a header line, then `<hashlet>  <date>  <msg>` rows.
function firstHashlet(text) {
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const w = lines[i].split(" ")[0];
    if (w.length < 6 || w.length > 40) continue;
    let hex = true;
    for (let j = 0; j < w.length; j++) {
      const c = w.charCodeAt(j);
      if (!((c >= 48 && c <= 57) || (c >= 97 && c <= 102))) { hex = false; break; }
    }
    if (hex) return w;
  }
  return "";
}

if (o !== null) main();
