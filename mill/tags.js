//  test/mill/tags.js — TEST-004: the tag treadmill.  Clone <uri> at its
//  first tag, then walk the worktree tag by tag with `jab get <uri>?tags/T`,
//  comparing against a parallel `git checkout` clone at EVERY hop.  Trees
//  identical or the hop FAILS — git is the oracle, per the ticket.
//
//  The JS port of beagle/beagle/test/mill-tags.sh, with the repo taken from
//  a URI argument instead of a hardcoded $HOME/src/git.
//
//  Run: jab test/mill/tags.js <uri> [--last N | --tags v6.1,v6.2] [--keep]
"use strict";

const m = require("./lib.js");

const SYNOPSIS =
  "tags.js — clone <uri>, then hop its worktree tag by tag (TEST-004)\n" +
  "\n" +
  "usage: jab test/mill/tags.js <uri> [options]\n" +
  "\n" +
  "  At every tag: `jab get <uri>?tags/T`, `git checkout T` in the reference\n" +
  "  clone, then `rsync -rlcni --delete` between the two worktrees.  Any\n" +
  "  difference fails the hop; a failed hop does not stop the run.";

const o = m.parseArgs(process.argv, "tags", SYNOPSIS);

function main() {
  m.need("git", "the tag list and the tree oracle both come from git");
  m.need("rsync", "the tree comparison is `rsync -rlcni --delete`");
  m.need("timeout", "every hop runs under a per-hop ceiling");

  const GITURL = m.refUrl(o);
  const ROOT = m.scratchRoot(o.id);
  const WT = ROOT + "/be";
  const REF = ROOT + "/git";

  //  --serve: `jab get` talks to a local `git upload-pack` over http while
  //  the oracle keeps cloning the repo directly.  The git URL is the source
  //  of truth either way.
  const server = o.serve ? m.serveGit(GITURL) : null;
  const SRC = server ? server.uri : o.uri;
  if (server) m.say("    serving  " + GITURL + " at " + server.uri);

  m.say("=== mill tags: " + o.uri);
  m.say("    jab      " + m.JAB_BIN);
  m.say("    oracle   " + GITURL);
  m.say("    scratch  " + ROOT + (o.keep ? "  (kept)" : ""));
  m.say("");

  const results = [];
  try {
    m.plantShard(ROOT, m.beRoot());
    m.shieldWt(WT);

    //  ---- the reference clone --------------------------------------------
    //  --no-checkout: the tags loop checks out one tag at a time, and a
    //  default checkout of a kernel-sized repo is pure waste.
    m.say("--- git clone --no-checkout (reference) ---");
    m.must("git clone", m.git(["clone", "--quiet", "--no-checkout", GITURL, REF],
                              { timeout: o.timeout, tee: true }));

    //  ---- the tag list ----------------------------------------------------
    let tags = o.tags;
    if (!tags) {
      const t = m.must("git tag", m.git(["-C", REF, "tag", "--sort=creatordate"],
                                        { timeout: o.timeout }));
      const all = t.out.split("\n").filter(function (x) { return x.length > 0; });
      if (all.length === 0) m.die("the repo has no tags — pass --tags with refs to walk");
      tags = o.last > 0 && all.length > o.last ? all.slice(all.length - o.last) : all;
      m.say("    " + all.length + " tags in the repo, walking the last " + tags.length);
    } else {
      m.say("    walking " + tags.length + " tag(s) given on the command line");
    }

    //  ---- the treadmill ---------------------------------------------------
    for (let i = 0; i < tags.length; i++) {
      const tag = tags[i];
      m.say("");
      m.say("=== [" + (i + 1) + "/" + tags.length + "] " + tag + " ===");

      //  Serialized be-then-git (mill-tags.sh): a concurrent `git checkout`
      //  in the reference clone races the fetch's own git plumbing.
      const g = m.run(m.JAB_BIN, [m.JAB_BIN, "get", SRC + "?tags/" + tag],
                      { cwd: WT, timeout: o.timeout, tee: true });
      if (g.timedOut) {
        results.push({ tag: tag, ok: false, why: "jab get timed out after " + o.timeout + "s",
                       wall: g.wall, rssKb: g.rssKb });
        m.say("FAIL  " + tag + ": jab get timed out");
        continue;
      }
      if (g.code !== 0) {
        results.push({ tag: tag, ok: false, why: "jab get exit " + g.code,
                       wall: g.wall, rssKb: g.rssKb });
        m.say("FAIL  " + tag + ": jab get exit " + g.code);
        continue;
      }

      const c = m.git(["-C", REF, "checkout", "--quiet", "--force", "refs/tags/" + tag],
                      { timeout: o.timeout });
      if (c.code !== 0) m.die("git checkout " + tag + " failed in the reference clone (exit " +
                              c.code + ")\n" + c.out.slice(0, 2000));

      const diffs = m.treeDiff(REF, WT);
      const files = m.wtFiles(WT);
      if (diffs.length === 0) {
        results.push({ tag: tag, ok: true, files: files, wall: g.wall, rssKb: g.rssKb });
        m.say("PASS  " + tag + "  " + files + " files, " + m.hms(g.wall) +
              (g.rssKb ? ", peak " + m.hb(g.rssKb * 1024) : ""));
      } else {
        results.push({ tag: tag, ok: false, why: diffs.length + " tree differences",
                       files: files, wall: g.wall, rssKb: g.rssKb });
        m.say("FAIL  " + tag + "  " + diffs.length + " tree differences:");
        for (let d = 0; d < diffs.length && d < 10; d++) m.say("      " + diffs[d]);
        if (diffs.length > 10) m.say("      … and " + (diffs.length - 10) + " more");
      }
    }
  } finally {
    if (server) server.stop();
    if (o.keep) m.say("\nscratch kept: " + ROOT);
    else m.rmrf(ROOT, ROOT);
  }

  //  ---- the tally ---------------------------------------------------------
  let bad = 0;
  m.say("");
  m.say("=== summary ===");
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    if (!r.ok) bad++;
    m.say("  " + (r.ok ? "PASS " : "FAIL ") + m.pad(r.tag, 20) +
          m.pad(m.hms(r.wall), 8) +
          m.pad(r.rssKb ? m.hb(r.rssKb * 1024) : "-", 12) +
          (r.ok ? r.files + " files" : r.why));
  }
  m.say("");
  m.say("=== " + results.length + " tags, " + bad + " failures ===");
  if (bad) m.die(bad + " tag(s) failed");
}

if (o !== null) main();
