//  test/mill/lib.js — TEST-004: shared plumbing for the MANUAL treadmills
//  (clone.js, tags.js).  Nothing here is a ctest case: test/CMakeLists.txt
//  globs `*/*/run.sh` and this dir carries none.  See README.mkd.
//
//  Everything a treadmill needs that jab does not hand it directly: a
//  subprocess runner with wall/peak-RSS/timeout, the $HOME/tmp scratch with
//  the repo-setup.sh shield+firewall, the rsync tree oracle, and the
//  `<uri>` → git-URL derivation (through the URI lexer, never a regex).
"use strict";

const urilib = require("../../shared/uri.js");
const pathlib = require("../../shared/util/path.js");

const HOME = io.getenv("HOME") || "";
//  Ceiling on the child output kept in this heap; past it we count and say so.
const OUT_CAP = 16 << 20;
const GIT_BIN = io.getenv("GIT_BIN") || "git";
const RSYNC_BIN = io.getenv("RSYNC_BIN") || "rsync";
const TIMEOUT_BIN = io.getenv("TIMEOUT_BIN") || "timeout";
//  `time -v` prints "Maximum resident set size (kbytes): N" — busybox and
//  GNU time agree on that line.  MILL_NO_TIME disables the wrapper.
const TIME_BIN = io.getenv("TIME_BIN") ||
                 (io.getenv("MILL_NO_TIME") ? "" : "/usr/bin/time");
const SCRATCH_BASE = io.getenv("MILL_TMP") || (HOME + "/tmp");
let rssSeq = 0;

//  Single-quote a path for `sh -c`.
function shq(s) { return "'" + String(s).split("'").join("'\\''") + "'"; }
//  The jab RUNNING THIS SCRIPT is the jab under test — never a $PATH lookup
//  that could resolve to a different build than the one being measured.
const JAB_BIN = (function () {
  try { return io.readlink("/proc/self/exe"); } catch (e) { return "jab"; }
})();

//  ---- reporting --------------------------------------------------------

function say(s) { console.log(s); }

//  Plain words at every failure boundary, never an ok64 code (the standing
//  ruling).  An uncaught throw is jab's exit 1 — that IS the failure exit.
function die(msg) { throw "mill: " + msg; }

function hb(n) {
  const u = ["B", "KiB", "MiB", "GiB", "TiB"];
  let i = 0, v = Number(n) || 0;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return (i ? v.toFixed(1) : String(v)) + " " + u[i];
}

function hms(ms) {
  const s = Math.round((Number(ms) || 0) / 1000);
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
  if (h) return h + "h" + (m < 10 ? "0" : "") + m + "m";
  if (m) return m + "m" + (x < 10 ? "0" : "") + x + "s";
  return x + "s";
}

function pad(s, n) { s = String(s); while (s.length < n) s += " "; return s; }

//  ---- small reads (/proc, logs) ----------------------------------------

//  One-shot read of a small file; null when it cannot be opened.  /proc
//  files report size 0, so io.readAll's stat-sized form is no use here.
function slurp(path, cap) {
  let fd;
  try { fd = io.open(path, "r"); } catch (e) { return null; }
  const b = new Uint8Array(cap || 8192);
  let n = 0;
  try { n = io._read(fd, b); } catch (e) { n = 0; } finally { io.close(fd); }
  return n > 0 ? utf8.Decode(b.slice(0, n)) : "";
}

//  Peak RSS (VmHWM, KiB) of `pid`; 0 when /proc says nothing.  VmHWM is a
//  high-water mark, so any late sample carries the whole run's peak.
function peakRss(pid) {
  const s = slurp("/proc/" + pid + "/status", 4096);
  if (!s) return 0;
  const lines = s.split("\n");
  for (let i = 0; i < lines.length; i++)
    if (lines[i].indexOf("VmHWM:") === 0)
      return Number(lines[i].slice(6).trim().split(" ")[0]) || 0;
  return 0;
}

//  First direct child of `pid` — the measured process when a run is wrapped
//  in `timeout` (whose own VmHWM is ~1 MiB and tells us nothing).
function firstChild(pid) {
  const s = slurp("/proc/" + pid + "/task/" + pid + "/children", 1024);
  if (!s) return 0;
  return Number(s.trim().split(" ")[0]) || 0;
}

//  Read a `time -v` capture: pull the max-RSS line out, hand back the rest
//  (the child's own stderr), and unlink the file.
function takeRss(path) {
  const txt = slurp(path, 1 << 20) || "";
  try { io.unlink(path); } catch (e) {}
  const lines = txt.split("\n"), keep = [];
  let rssKb = 0;
  for (let i = 0; i < lines.length; i++) {
    //  `time -v`'s own ~20 rusage lines are TAB-indented; anything else in
    //  this file is the child's stderr and must survive.
    if (lines[i].charAt(0) === "\t") {
      if (lines[i].indexOf("Maximum resident set size") > 0)
        rssKb = Number(lines[i].slice(lines[i].lastIndexOf(":") + 1).trim()) || 0;
    } else if (lines[i].length) keep.push(lines[i]);
  }
  return { rssKb: rssKb, text: keep.join("\n") };
}

//  ---- subprocess -------------------------------------------------------

//  run(bin, argv, opts) → { code, signal, timedOut, wall, rssKb, out }
//
//  `argv` INCLUDES argv[0] (io.spawn consumes the first element as argv0).
//  stdout is drained over pol (the curlRun pattern) and kept; stderr is
//  INHERITED, so a child's progress stays on the operator's terminal.  A
//  piped stdout also means no tty, hence no pager (BRO-027).
//  Peak RSS comes from `time -v` (its "Maximum resident set size"), not from
//  polling /proc: pol.run BLOCKS until the watched fd is ready, so a child
//  that runs minutes between writes gets no sample points at all, and at EOF
//  the process is already gone.  `time` measures the whole subtree via
//  wait4 rusage and is exact.
//  opts: { cwd, timeout (seconds, 0 = none), tee (echo stdout live) }.
function run(bin, argv, opts) {
  opts = opts || {};
  const tmo = opts.timeout || 0;
  let sbin = bin, sargv = (argv || []).slice();
  //  `timeout -k` because a wedged indexer may ignore the first TERM; 124
  //  is its "the budget ran out" code.
  if (tmo > 0) { sargv = [TIMEOUT_BIN, "-k", "10", String(tmo)].concat(sargv); sbin = TIMEOUT_BIN; }
  //  `time -v` reports to STDERR (busybox has no `-o FILE`), so the pair
  //  runs under a shell that sends that stderr to a scratch file.  The
  //  child's own stderr rides along; it is read back and appended to `out`,
  //  so nothing is lost — only its liveness.
  let rssFile = null;
  if (opts.rss && TIME_BIN) {
    rssFile = SCRATCH_BASE + "/mill-rss-" + io.getpid() + "-" + (rssSeq++);
    sargv = ["sh", "-c", '{ "$0" -v "$@"; } 2>' + shq(rssFile), TIME_BIN].concat(sargv);
    sbin = "sh";
  }
  const back = opts.cwd ? io.cwd() : null;
  if (back) io.chdir(opts.cwd);
  const t0 = Date.now();
  let child = null;
  try { child = io.spawn(sbin, sargv); }
  catch (e) {
    if (back) io.chdir(back);
    die("cannot spawn '" + sbin + "' (" + e + ") — is it installed and in $PATH?");
  }
  io.close(child.stdin);

  const chunks = [];
  let total = 0, dropped = 0, done = false;
  const scratch = new Uint8Array(1 << 16);
  pol.watch(child.stdout, pol.IN, function (fd) {
    const n = io._read(fd, scratch);
    if (n <= 0) { done = true; io.close(fd); return 0; }
    const c = scratch.slice(0, n);
    if (opts.tee) io.writeAll(1, c);
    //  Keep at most OUT_CAP: a chatty child at kernel scale (`git
    //  verify-pack -v` is ~11.7M lines) would otherwise pull its whole
    //  output into this heap.  Truncation is REPORTED, never silent.
    if (total < OUT_CAP) { chunks.push(c); total += n; } else dropped += n;
    return pol.IN;
  });
  let guard = 0;
  while (!done && guard++ < 100000000) pol.run(100 * pol.MS);
  const wall = Date.now() - t0;
  let rc = {};
  try { rc = io.reap(child.pid); } catch (e) {}
  if (!done) { try { pol.unwatch(child.stdout); io.close(child.stdout); } catch (e) {} }
  if (back) io.chdir(back);

  const bytes = new Uint8Array(total);
  let off = 0;
  for (let i = 0; i < chunks.length; i++) { bytes.set(chunks[i], off); off += chunks[i].length; }
  let out = utf8.Decode(bytes);
  if (dropped) out += "\n…[" + dropped + " further bytes of output dropped]";
  let rssKb = 0;
  if (rssFile) {
    const cap = takeRss(rssFile);
    rssKb = cap.rssKb;
    if (cap.text) out += (out.length ? "\n" : "") + cap.text;
  }
  return { code: rc.code === undefined ? -1 : rc.code, signal: rc.signal,
           timedOut: rc.code === 124, wall: wall, rssKb: rssKb,
           dropped: dropped, out: out };
}

function git(argv, opts) { return run(GIT_BIN, [GIT_BIN].concat(argv), opts); }

//  Run and die on failure — for the setup steps where a non-zero exit means
//  the environment is wrong, not the product ([Issues]: report, never
//  improvise a fallback).
function must(what, r) {
  if (r.timedOut) die(what + " timed out");
  if (r.code !== 0) die(what + " failed (exit " + r.code + ")\n" + r.out.slice(0, 2000));
  return r;
}

//  Fail early and in plain words when a required tool is missing.
function need(bin, why) {
  const r = run("sh", ["sh", "-c", "command -v '" + bin + "' >/dev/null 2>&1"], {});
  if (r.code !== 0) die("'" + bin + "' is not in $PATH — " + why);
}

//  ---- scratch ----------------------------------------------------------

//  Scratch lives under $HOME/tmp (ext4: the store mmaps need it), NEVER in
//  the source tree — `be` climbs for a `.be` anchor and a scratch worktree
//  inside the project would glue onto the project's own store.
function scratchRoot(id) {
  if (!HOME) die("$HOME is unset — the treadmill needs an ext4 scratch under it");
  const base = io.getenv("MILL_TMP") || (HOME + "/tmp");
  io.mkdir(base);
  //  The hermetic firewall (test/lib/repo-setup.sh rs_firewall): an EMPTY
  //  `.be` FILE at the base is an INVALID anchor, so a walk that escapes a
  //  broken wt shield stops here instead of reaching the real $HOME/.be.
  try { io.stat(base + "/.be"); } catch (e) { try { io.close(io.open(base + "/.be", "c")); } catch (e2) {} }
  const root = base + "/mill-" + id + "-" + io.getpid();
  io.mkdir(root);
  return root;
}

//  The scratch worktree is a BARE EMPTY DIR — deliberately NOT repo-setup's
//  empty-`.be/` shield.  Pre-seeding `.be/` makes the FIRST `jab get` into
//  it die in `hashlet60FromBytes` ("Invalid argument type in ToBigInt
//  operation", via locate ← getObject ← commitTree ← fanoutWholeTree) while
//  a second get succeeds; verified 2026-07-27, see [TEST-004] §Blockers.
//  Isolation still holds: scratchRoot's `.be` firewall FILE sits above and
//  stops the climb before the dev box's real $HOME/.be.
function shieldWt(dir) { io.mkdir(dir); }

//  jab resolves bareword verbs from a `jsrc/` shard up the cwd chain, so
//  plant one above the scratch pointing at THIS be/ tree — the `jab get`
//  children must run the code under test, not $HOME/jsrc.
function plantShard(root, beRoot) {
  const link = root + "/jsrc";
  try { io.unlink(link); } catch (e) {}
  io.symlink(beRoot, link);
}

//  The be/ worktree hosting this script (test/mill/lib.js → three up).
function beRoot() {
  return pathlib.dirname(pathlib.dirname(pathlib.dirname(io.realpath(process.argv[1]))));
}

//  Recursive delete, refused outside the scratch root: the treadmill never
//  removes anything it did not create.
function rmrf(root, path) {
  if (path !== root && path.indexOf(root + "/") !== 0)
    die("refusing to delete outside the scratch root: " + path);
  must("rm -rf " + path, run("rm", ["rm", "-rf", path], {}));
}

//  Disk footprint of a path in bytes (via `du -sk`), 0 when du says nothing.
function duBytes(path) {
  const r = run("du", ["du", "-sk", path], {});
  if (r.code !== 0) return 0;
  return (Number(r.out.split("\t")[0].trim()) || 0) * 1024;
}

//  ---- a local smart-HTTP server ----------------------------------------

//  `--serve`: wrap a LOCAL git repo in serve.py's `git upload-pack` and
//  hand back the http URI to clone from.  The box may have no sshd, a bare
//  path is not a remote, and `be:`/`file:` want a beagle store — this is
//  the only local transport left for a vanilla git mirror.  Note the
//  ceiling it inherits: curlRun buffers the whole response in the JS heap
//  ([KEEP-006] §Blockers), so this reaches test repos, NOT the kernel.
//  Returns { uri, stop() }.
function serveGit(repoPath) {
  need("python3", "--serve wraps `git upload-pack` in test/mill/serve.py");
  const script = pathlib.dirname(io.realpath(process.argv[1])) + "/serve.py";
  const child = io.spawn("python3", ["python3", script, repoPath]);
  io.close(child.stdin);
  //  serve.py prints its bound port as its first line, then serves.
  const b = new Uint8Array(64);
  let port = 0, spins = 0;
  while (!port && spins++ < 200) {
    const n = io._read(child.stdout, b);
    if (n > 0) port = Number(utf8.Decode(b.slice(0, n)).trim()) || 0;
    else pol.sleep(50 * pol.MS);
  }
  if (!port) { try { io.reap(child.pid); } catch (e) {} die("serve.py did not report a port"); }
  const name = pathlib.basename(repoPath.charAt(repoPath.length - 1) === "/"
                                ? repoPath.slice(0, repoPath.length - 1) : repoPath);
  //  NO `?/<project>` selector: the query slot holds EITHER a project
  //  selector OR the in-band `?ref` want (wire.js classify), never both,
  //  and the tag walk needs the ref half.
  return {
    uri: "http://127.0.0.1:" + port + "/" + name,
    stop: function () {
      try { run("kill", ["kill", String(child.pid)], {}); } catch (e) {}
      try { io.reap(child.pid); } catch (e) {}
      try { io.close(child.stdout); } catch (e) {}
    },
  };
}

//  ---- the oracle -------------------------------------------------------

//  rsync -rlcni --delete: CHECKSUM-compare ref → wt and list every
//  difference (`--delete` also reports files present only in wt).  An empty
//  list IS the assertion — the mill-tags.sh oracle, kept verbatim.
function treeDiff(ref, wt) {
  //  UNANCHORED excludes: a submodule carries its own `.git` (git's side)
  //  and `.be` (beagle's mount) one level down, so `/​.git/`-style anchored
  //  patterns leave that metadata in the comparison and it reads as a
  //  content difference.  Both are store metadata wherever they appear.
  const r = run(RSYNC_BIN, [RSYNC_BIN, "-rlcni", "--delete",
    "--exclude=.git", "--exclude=.git/", "--exclude=.be", "--exclude=.be/",
    "--exclude=..be.idx",
    ref + "/", wt + "/"], {});
  if (r.code !== 0) die("rsync failed (exit " + r.code + ")\n" + r.out.slice(0, 2000));
  const lines = r.out.split("\n");
  const diffs = [];
  for (let i = 0; i < lines.length; i++) if (lines[i].length) diffs.push(lines[i]);
  return diffs;
}

//  Count the content files in a worktree (store + git metadata excluded).
function wtFiles(dir) {
  const r = run("sh", ["sh", "-c", "find '" + dir + "' -type f " +
    "-not -path '*/.be/*' -not -path '*/.git/*' -not -name '..be.idx' | wc -l"], {});
  return Number(r.out.trim()) || 0;
}

//  ---- URIs -------------------------------------------------------------

//  The git oracle needs a URL GIT can clone.  Derive it from `<uri>` BY
//  SCHEME through the native lexer (uri.parse), never by string surgery:
//  http(s)/ssh/git pass through, `file:/p` is its path, a bare path is
//  itself.  A beagle-only source (be:, //wt, ///sub) has no git equivalent
//  — say so and ask for --ref-uri instead of guessing one.
function gitUrlFor(arg) {
  const u = urilib.parse(arg);
  if (typeof u === "string") return u;                    // not a URI: a path
  const s = u.scheme;
  if (s === undefined) return u.authority === undefined ? (u.path || arg) : null;
  if (s === "file") return u.path || null;
  if (s !== "http" && s !== "https" && s !== "ssh" && s !== "git") return null;
  if (u.query === undefined && u.fragment === undefined) return u.href;
  const bare = URI.make(s, u.authority, u.path, undefined, undefined);
  return bare || null;
}

//  ---- args -------------------------------------------------------------

//  Byte sizes take a k/M/G suffix — a 2 GiB cap is unreadable in digits.
function size(s) {
  const t = String(s).trim();
  const mul = { k: 1024, K: 1024, m: 1 << 20, M: 1 << 20, g: 1 << 30, G: 1 << 30 };
  const last = t.charAt(t.length - 1);
  const n = Number(mul[last] ? t.slice(0, t.length - 1) : t);
  if (!isFinite(n) || n < 0) die("'" + s + "' is not a byte size (try 512M, 2G)");
  return Math.floor(n * (mul[last] || 1));
}

//  `<uri>` is a POSITIONAL with NO default — TEST-004 takes the repo from
//  the caller (local mirror or github), never a hardcoded $HOME/src/git.
const USAGE_TAIL = [
  "",
  "  <uri>            repo to clone, e.g. be://localhost/mirror/linux,",
  "                   file:/srv/mirror/linux, https://github.com/torvalds/linux",
  "",
  "  --ref-uri U      URL for the GIT oracle clone (default: derived from <uri>)",
  "  --tags a,b,c     explicit tag list (default: the last --last tags)",
  "  --last N         use the N most recent tags by creation date (default 10)",
  "  --timeout S      per-step ceiling in seconds, 0 = none (default 3600)",
  "  --keep           keep the scratch dir on exit (default: delete it)",
  "  --serve          wrap a LOCAL git repo in a smart-HTTP server and clone",
  "                   from that (no sshd needed; small repos only)",
  "  --id NAME        scratch dir name suffix (default: the script's name)",
  "",
  "Scratch: $MILL_TMP or $HOME/tmp.  Tools: git, rsync, timeout, du, rm.",
].join("\n");

function parseArgs(argv, name, synopsis) {
  const o = { uri: null, refUri: null, tags: null, last: 10, timeout: 3600,
              keep: false, id: name, refClone: false,
              cap: 0, mode: "both", buf: 1 << 30, keepRepo: null, serve: false };
  const rest = argv.slice(2);
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    const val = function (what) {
      if (i + 1 >= rest.length) die(what + " needs a value");
      return rest[++i];
    };
    if (a === "--help" || a === "-h") { say(synopsis + "\n" + USAGE_TAIL); return null; }
    else if (a === "--ref-uri") o.refUri = val("--ref-uri");
    else if (a === "--tags") o.tags = val("--tags").split(",").filter(function (t) { return t.length; });
    else if (a === "--last") o.last = Number(val("--last")) || 0;
    else if (a === "--timeout") o.timeout = Number(val("--timeout")) || 0;
    else if (a === "--id") o.id = val("--id");
    else if (a === "--keep") o.keep = true;
    else if (a === "--serve") o.serve = true;
    else if (a === "--ref-clone") o.refClone = true;
    else if (a === "--cap") o.cap = size(val("--cap"));
    else if (a === "--buf") o.buf = size(val("--buf"));
    else if (a === "--keep-repo") { o.keepRepo = val("--keep-repo"); o.keep = true; }
    else if (a === "--mode") {
      o.mode = val("--mode");
      if (o.mode !== "file" && o.mode !== "pipe" && o.mode !== "both")
        die("--mode takes file, pipe or both, not '" + o.mode + "'");
    }
    else if (a.indexOf("-") === 0) die("unknown option '" + a + "' (try --help)");
    else if (o.uri === null) o.uri = a;
    else die("unexpected extra argument '" + a + "' (try --help)");
  }
  if (o.uri === null) die("no <uri> given — the repo to clone is a required argument (try --help)");
  return o;
}

//  Resolve the git-oracle URL: explicit --ref-uri wins, else derive.
function refUrl(o) {
  if (o.refUri) return o.refUri;
  const g = gitUrlFor(o.uri);
  if (!g) die("cannot derive a git URL from '" + o.uri + "' — pass --ref-uri with a URL git can clone");
  return g;
}

module.exports = {
  say: say, die: die, hb: hb, hms: hms, pad: pad,
  slurp: slurp, peakRss: peakRss,
  run: run, git: git, must: must, need: need,
  JAB_BIN: JAB_BIN, GIT_BIN: GIT_BIN,
  scratchRoot: scratchRoot, shieldWt: shieldWt, plantShard: plantShard,
  beRoot: beRoot, rmrf: rmrf, duBytes: duBytes,
  treeDiff: treeDiff, wtFiles: wtFiles, serveGit: serveGit,
  gitUrlFor: gitUrlFor, parseArgs: parseArgs, refUrl: refUrl, size: size,
};
